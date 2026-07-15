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

# @description Collects scope, starting and ending lines for the given elements
# names.
#
# Elements are extracted from the environment's manifest file and appended to
# the given arrays. Element traits collected will be at the same position as
# element name in names array.
#
# If no elements are requested, the function is a no-op.
#
# If requested element does not exist, its traits are null.
#
# @arg $1 string Environment path.
# @arg $2 array  Constant reference to names array.
# @arg $3 array  Reference to lines array.
# @arg $4 array  Reference to scopes array.
# @arg $5 array  Reference to kinds array
# @arg $6 array  Reference to starting lines array.
# @arg $7 array  Reference to ending lines array.
#
# @see Used in 
_bl_manifest_collect_traits_by_name() {
    
    local -r ENVIRONMENT="$1"
    local -rn NAMES=$2
    local -n lines_=$3
    local -n scopes_=$4
    local -n kinds_=$5
    local -n starts_=$6
    local -n ends_=$7

    [[ "${#NAMES[@]}" -ne 0 ]] || return 0

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    mapfile -t MANIFEST_LINES < \
        "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
    
    # Turn MANIFEST_LINES array into map for faster lookup
    local -A elements
    for (( _i_ = 1; _i_ < ${#MANIFEST_LINES[@]}; _i_++ )); do

        read -r name scope kind start end <<< "${MANIFEST_LINES[_i_]}"
        elements["$name"]="$_i_ $scope $kind $start $end"
    done

    # Collect elements from map
    for (( pos = 0; pos < "${#NAMES[@]}"; pos++)); do

        # Check if the element exists
        if [[ -n ${elements[${NAMES[pos]}]+x} ]]; then
            read -r line scope kind start end <<< "${elements[${NAMES[pos]}]}"

            lines_[pos]="$line"
            scopes_[pos]="$scope"
            kinds_[pos]="$kind"
            starts_[pos]="$start"
            ends_[pos]="$end"
        fi
    done
}

# @description Collects elements' name from an environment's manifest.
#
# Depending on the provided flags, local and/or scoped elements are extracted
# from the environment's manifest file and appended to the given arrays.
#
# If neither local nor scoped elements are requested, the function is a no-op.
#
# @arg $1 string Environment path.
# @arg $2 bool   Whether to collect local elements.
# @arg $3 bool   Whether to collect scoped elements.
# @arg $4 array  Reference to aliases array.
# @arg $5 array  Reference to functions array.
# @arg $6 array  Reference to variables array.
#
# @see Used in [_bl_core_resolve_prunable_elements]
# (#_bl_core_resolve_prunable_elements)
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
    mapfile -t MANIFEST_LINES < \
        "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    local -r SCOPED_OFFSET="${MANIFEST_LINES[0]}"

    # Decide the lines to read
    local INITIAL_LINE=1
    local END_LINE="${#MANIFEST_LINES[@]}"
    [[ "$COLLECT_LOCAL_ELEMENTS" == false ]] && INITIAL_LINE="$SCOPED_OFFSET"
    [[ "$COLLECT_SCOPED_ELEMENTS" == false ]] && END_LINE="$SCOPED_OFFSET"

    # Collect elements from array
    local i
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
# - Writes: manifest file
#
# @arg $1 string Environment path.
# @arg $2 array  Constant reference to names array.
# @arg $3 array  Constant reference to scopes array.
# @arg $4 array  Constant reference to kinds array.
# @arg $5 array  Constant reference to starting lines array.
# @arg $6 array  Constant reference to ending lines array.
#
# @exitcode 1 If arrays ($2-$6) have a different number of elements.
# @exitcode 2 If writing in manifest file fails.
#
# @see Used in 
_bl_manifest_append_by_traits() {
    
    local -r ENVIRONMENT="$1"
    local -rn NAMES=$2
    local -rn SCOPES=$3
    local -rn KINDS=$4
    local -rn STARTS=$5
    local -rn ENDS=$6

    [[ "${#NAMES[@]}" -eq "${#SCOPES[@]}" && \
       "${#NAMES[@]}" -eq "${#KINDS[@]}" && \
       "${#NAMES[@]}" -eq "${#STARTS[@]}" && \
       "${#NAMES[@]}" -eq "${#ENDS[@]}" ]] || return 1
    [[ "${#NAMES[@]}" -ne 0 ]] || return 0

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    mapfile -t MANIFEST_LINES < \
        "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    # starts and ends should be ordered
    for (( pos = 0; pos < ${#NAMES[@]}; pos++ )); do

        local scoped_offset="${MANIFEST_LINES[0]}"

        # Turn traits into single line
        local element_line
        printf -v element_line '%s %s %s %s %s' \
            "${NAMES[pos]}" \
            "${SCOPES[pos]}" \
            "${KINDS[pos]}" \
            "${STARTS[pos]}" \
            "${ENDS[pos]}"

        if [[ "${SCOPES[pos]}" == "${_BL_CONST[MANIFEST_SCHEMA_SCOPE_LOCAL]}" ]]; then

            # Move elements one position right
            for (( _i_ = ${#MANIFEST_LINES[@]}; _i_ > scoped_offset; _i_-- )); do
                MANIFEST_LINES[_i_]="${MANIFEST_LINES[_i_-1]}"
            done

            # Insert element
            MANIFEST_LINES[scoped_offset]="$element_line"
            MANIFEST_LINES[0]="$(( scoped_offset+1 ))"

        elif [[ "${SCOPES[pos]}" == "${_BL_CONST[MANIFEST_SCHEMA_SCOPE_SCOPED]}" ]]; then
            MANIFEST_LINES+=("$element_line")
        fi
    done
    
    # Atomic write in manifest file
    local tmp
    tmp="$(mktemp)" || return 2
    printf '%s\n' "${MANIFEST_LINES[@]}" > "$tmp"
    mv "$tmp" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
}


# MARK: Remove
# -----------------------------------------------------------------------------
# @section Remove elements

# @description Removes elements from an environment's manifest
#
# If no elements given, the function is a no-op.
#
# Side effects:
# - Writes: manifest file
#
# @arg $1 string Environment path.
# @arg $2 array  Constant reference to names array.
# @arg $3 array  Constant reference to lines array.
#
# @exitcode 1 If arrays ($2-$6) have different number of elements.
# @exitcode 2 If writing in manifest file fails.
#
# @see Used in 
_bl_manifest_remove_by_lines() {
    
    local -r ENVIRONMENT="$1"
    local -rn NAMES=$2
    local -rn LINES=$3

    [[ "${#NAMES[@]}" -eq "${#LINES[@]}" ]] || return 1
    [[ "${#NAMES[@]}" -ne 0 ]] || return 0

    # Map manifest into MANIFEST_LINES array
    local -a MANIFEST_LINES
    mapfile -t MANIFEST_LINES < \
        "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    local i
    for (( i = 0; i < ${#NAMES[@]}; i++ )); do

        local scoped_offset="${MANIFEST_LINES[0]}"
        local name="${NAMES[i]}"
        local line="${LINES[i]}"

        # Move elements one position left
        local j
        for (( j = line; j < ${#MANIFEST_LINES[@]} - 1; j++ )); do
            MANIFEST_LINES[j]="${MANIFEST_LINES[j+1]}"
        done

        # Remove last line
        unset "MANIFEST_LINES[${#MANIFEST_LINES[@]}-1]"
        if [[ "$line" -lt "$scoped_offset" ]]; then
            MANIFEST_LINES[0]="$(( scoped_offset-1 ))"
        fi
    done
    
    # Atomic write in manifest file
    local tmp
    tmp="$(mktemp)" || return 2
    printf '%s\n' "${MANIFEST_LINES[@]}" > "$tmp"
    mv "$tmp" "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
}