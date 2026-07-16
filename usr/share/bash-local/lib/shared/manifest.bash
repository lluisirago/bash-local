#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file manifest.bash
#
# @brief Manifest files manager.
# @description Implements functions responsible for accessing manifest files.
# They collect, append and remove rows from/to the files.

# MARK: Collect
# -----------------------------------------------------------------------------
# @section Collect elements traits
#
# Functions in this section collect traits from multiple elements.

# @description Collects line number, scope, kind, and starting and ending lines
# for the given elements names.
#
# Elements are extracted from the environment's manifest file and appended to
# the given arrays. Element traits collected will be at the same position as
# element name in names array.
#
# If no elements are requested, the function is a no-op.
# If requested element does not exist, its traits are null.
#
# Side effects:
# - Reads manifest file.
#
# @arg $1 string Environment path (without trailing '/').
# @arg $2 array  Constant reference to names array.
# @arg $3 array  Reference to line numbers array.
# @arg $4 array  Reference to scopes array.
# @arg $5 array  Reference to kinds array
# @arg $6 array  Reference to starting lines array.
# @arg $7 array  Reference to ending lines array.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[PATH_MANIFEST]` is not defined or is empty.
# @exitcode 2 Manifest file does not exist.
# @exitcode 3 Manifest file does not have reading permissions.
# @exitcode 4 Reading manifest file failed.
_bl_manifest_collect_traits_by_name() {
    
    local -r ENVIRONMENT="$1"
    local -rn NAMES=$2
    local -n linenos_=$3
    local -n scopes_=$4
    local -n kinds_=$5
    local -n starts_=$6
    local -n ends_=$7

    [[ "${#NAMES[@]}" -ne 0 ]] || return 0

    if ! [[ -n "${_BL_CONST[PATH_MANIFEST]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_MANIFEST]"
        return 1
    elif ! [[ -f "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}" ]]; then
        bl_log "FATAL_NO_FILE" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
        return 2
    elif ! [[ -r "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}" ]]; then
        bl_log "FATAL_NO_PERM" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
        return 3
    fi

    local -r MANIFEST="$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    if ! mapfile -t MANIFEST_LINES < "$MANIFEST"; then
        bl_log_debug "FATAL_READ" "$MANIFEST"
        return 4
    fi

    # Turn MANIFEST_LINES array into map for faster lookup
    local -A elements
    local -i i
    for (( i = 1; i < ${#MANIFEST_LINES[@]}; i++ )); do

        read -r name scope kind start end <<< "${MANIFEST_LINES[i]}"
        elements["$name"]="$i $scope $kind $start $end"
    done

    # Collect elements from map
    for (( i = 0; i < "${#NAMES[@]}"; i++)); do

        # Check if element exists
        if [[ -v "elements[${NAMES[i]}]" ]]; then
            read -r lineno scope kind start end <<< "${elements[${NAMES[i]}]}"

            linenos_[i]="$lineno"
            scopes_[i]="$scope"
            kinds_[i]="$kind"
            starts_[i]="$start"
            ends_[i]="$end"
        fi
    done
}

# @description Collects names of elements in an environment's manifest for given
# scopes.
#
# Depending on the provided flags, local and/or scoped elements are extracted
# from the environment's manifest file and appended to the given arrays.
#
# If neither local nor scoped elements are requested, the function is a no-op.
#
# This function performs no validation because it is used internally by the 
# core for efficiency.
#
# Side effects:
# - Reads manifest file.
#
# @arg $1 string Environment path (without trailing '/').
# @arg $2 bool   Whether to collect local elements.
# @arg $3 bool   Whether to collect scoped elements.
# @arg $4 array  Reference to aliases array.
# @arg $5 array  Reference to functions array.
# @arg $6 array  Reference to variables array.
#
# @exitcode 0 Success.
_bl_manifest_collect_names_by_scope() {

    local -r ENVIRONMENT="$1"
    local -r COLLECT_LOCAL_ELEMENTS="$2"
    local -r COLLECT_SCOPED_ELEMENTS="$3"
    local -n aliases__=$4
    local -n functions__=$5
    local -n variables__=$6
    
    [[ "$COLLECT_LOCAL_ELEMENTS" == true ||
       "$COLLECT_SCOPED_ELEMENTS" == true ]] || return 0

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    mapfile -t MANIFEST_LINES < "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    local -r SCOPED_OFFSET="${MANIFEST_LINES[0]}"

    # Decide lines to read
    local INITIAL_LINE=1
    local END_LINE="${#MANIFEST_LINES[@]}"
    [[ "$COLLECT_LOCAL_ELEMENTS" == false ]] && INITIAL_LINE="$SCOPED_OFFSET"
    [[ "$COLLECT_SCOPED_ELEMENTS" == false ]] && END_LINE="$SCOPED_OFFSET"

    # Collect elements from array
    local -i i
    for (( i = INITIAL_LINE; i < END_LINE; i++ )); do

        read -r name scope kind first last <<< "${MANIFEST_LINES[i]}"

        case "$kind" in
            "${_BL_CONST[MANIFEST_SCHEMA_KIND_ALIAS]}") aliases__+=("$name");;
            "${_BL_CONST[MANIFEST_SCHEMA_KIND_FUNCTION]}") functions__+=("$name");;
            "${_BL_CONST[MANIFEST_SCHEMA_KIND_VARIABLE]}") variables__+=("$name");;
        esac
    done
}


# MARK: Append
# -----------------------------------------------------------------------------
# @section Append elements

# @description Appends elements to an environment's manifest. Inserts the
# element at the end of its scope's section.
#
# Elements given MUST be ordered by starting lines (or ending lines).
#
# If no elements given, the function is a no-op.
#
# Side effects:
# - Reads and writes manifest file.
#
# @arg $1 string Environment path (without trailing '/').
# @arg $2 array  Constant reference to names array.
# @arg $3 array  Constant reference to scopes array.
# @arg $4 array  Constant reference to kinds array.
# @arg $5 array  Constant reference to starting lines array.
# @arg $6 array  Constant reference to ending lines array.
#
# @exitcode 0 Success.
# @exitcode 1 Arrays ($2-$6) have a different number of elements.
# @exitcode 2 `_BL_CONST[PATH_MANIFEST]` is not defined or is empty.
# @exitcode 3 Manifest file does not exist.
# @exitcode 4 Manifest file does not have reading permissions.
# @exitcode 5 Reading manifest file failed.
# @exitcode 6 Writing in manifest file failed.
_bl_manifest_append_by_traits() {
    
    local -r ENVIRONMENT="$1"
    local -rn NAMES=$2
    local -rn SCOPES=$3
    local -rn KINDS=$4
    local -rn STARTS=$5
    local -rn ENDS=$6

    local size=${#NAMES[@]}
    [[ size -ne 0 ]] || return 0

    # shellcheck disable=SC2056
    if (( size != ${#SCOPES[@]} || size != ${#KINDS[@]}  ||
          size != ${#STARTS[@]} || size != ${#ENDS[@]} )); then

        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi

    if ! [[ -n "${_BL_CONST[PATH_MANIFEST]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_MANIFEST]"
        return 2
    elif ! [[ -f "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}" ]]; then
        bl_log "FATAL_NO_FILE" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
        return 3
    elif ! [[ -r "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}" ]]; then
        bl_log "FATAL_NO_PERM" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
        return 4
    fi

    local -r MANIFEST="$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    if ! mapfile -t MANIFEST_LINES < "$MANIFEST"; then
        bl_log_debug "FATAL_READ" "$MANIFEST"
        return 5
    fi

    local -i i
    for (( i = 0; i < ${#NAMES[@]}; i++ )); do

        local scoped_offset="${MANIFEST_LINES[0]}"

        # Turn traits into single line
        local element_line
        printf -v element_line '%s %s %s %s %s' \
            "${NAMES[i]}" \
            "${SCOPES[i]}" \
            "${KINDS[i]}" \
            "${STARTS[i]}" \
            "${ENDS[i]}"

        if [[ "${SCOPES[i]}" == "${_BL_CONST[MANIFEST_SCHEMA_SCOPE_LOCAL]}" ]]; then

            # Move elements one position right
            local -i j
            for (( j = ${#MANIFEST_LINES[@]}; j > scoped_offset; j-- )); do
                MANIFEST_LINES[j]="${MANIFEST_LINES[j-1]}"
            done

            # Insert element
            MANIFEST_LINES[scoped_offset]="$element_line"
            MANIFEST_LINES[0]="$(( scoped_offset+1 ))"

        elif [[ "${SCOPES[i]}" == "${_BL_CONST[MANIFEST_SCHEMA_SCOPE_SCOPED]}" ]]; then
            MANIFEST_LINES+=("$element_line")
        fi
    done
    
    bl_atomic_write MANIFEST_LINES "$MANIFEST" || return 6
}


# MARK: Remove
# -----------------------------------------------------------------------------
# @section Remove elements

# @description Removes elements from an environment's manifest given line
# number.
#
# If no line numbers given, function is a no-op.
#
# Side effects:
# - Reads and writes manifest file.
#
# @arg $1 string Environment path (without trailing '/').
# @arg $2 array  Constant reference to line numbers array.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[PATH_MANIFEST]` is not defined or is empty.
# @exitcode 2 Manifest file does not exist.
# @exitcode 3 Manifest file does not have reading permissions.
# @exitcode 4 Reading manifest file failed.
# @exitcode 5 Writing in manifest file failed.
_bl_manifest_remove_by_lineno() {
    
    local -r ENVIRONMENT="$1"
    local -rn LINENOS=$2

    [[ "${#LINENOS[@]}" -ne 0 ]] || return 0

    if ! [[ -n "${_BL_CONST[PATH_MANIFEST]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_MANIFEST]"
        return 1
    elif ! [[ -f "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}" ]]; then
        bl_log "FATAL_NO_FILE" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
        return 2
    elif ! [[ -r "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}" ]]; then
        bl_log "FATAL_NO_PERM" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
        return 3
    fi

    local -r MANIFEST="$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    if ! mapfile -t MANIFEST_LINES < "$MANIFEST"; then
        bl_log_debug "FATAL_READ" "$MANIFEST"
        return 4
    fi

    local -i i
    for (( i = 0; i < ${#LINENOS[@]}; i++ )); do

        local scoped_offset="${MANIFEST_LINES[0]}"
        local lineno="${LINENOS[i]}"

        # Move elements one position left
        local -i j
        for (( j = lineno; j < ${#MANIFEST_LINES[@]} - 1; j++ )); do
            MANIFEST_LINES[j]="${MANIFEST_LINES[j+1]}"
        done

        # Remove last line
        unset "MANIFEST_LINES[${#MANIFEST_LINES[@]}-1]"
        if [[ "$lineno" -lt "$scoped_offset" ]]; then
            MANIFEST_LINES[0]="$(( scoped_offset-1 ))"
        fi
    done
    
    bl_atomic_write MANIFEST_LINES "$MANIFEST" || return 5
}