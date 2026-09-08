#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file source.bash
#
# @brief Source files manager.
# @description Implements functions responsible for accessing source files.
# They collect, append and remove rows from/to the files.

# MARK: Append
# -----------------------------------------------------------------------------
# @section Append elements

# @description Appends elements to a source file. Inserts the element at the end
# of the file.
#
# Starting and ending lines will be ordered by element position in arrays.
#
# If no elements given, the function is a no-op.
#
# Side effects:
# - Reads and writes source file.
#
# @arg $1 string Environment path (without trailing '/').
# @arg $2 string  Scope.
# @arg $3 array  Constant reference to kinds array.
# @arg $4 array  Constant reference to names array.
# @arg $5 array  Constant reference to sources array.
# @arg $6 array  Reference to starting lines array.
# @arg $7 array  Constant reference to ending lines array.
#
# @exitcode 0 Success.
# @exitcode 1 Arrays ($3-$5) have a different number of elements (logged in
# debug).
# @exitcode 2 `_BL_CONST["PATH_SOURCE_$SCOPE"]` is not defined or is empty
# (logged in debug).
# @exitcode 3 Source file does not exist (logged).
# @exitcode 4 Source file does not have reading or writing permissions (logged).
# @exitcode 5 Reading failed (logged in debug).
# @exitcode 6 Building definition failed (logged in debug).
# @exitcode 7 Writing failed (logged in debug).
bl_source_append_by_scope() {
    
    local -r ENVIRONMENT="$1"
    local -r SCOPE="$2"
    local -rn KINDS=$3
    local -rn NAMES=$4
    local -rn SOURCES=$5
    local -n starts_=$6
    local -n ends_=$7

    local size=${#NAMES[@]}
    [[ size -ne 0 ]] || return 0

    # shellcheck disable=SC2056
    if (( size != ${#KINDS[@]} || size != ${#SOURCES[@]} )); then

        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi
    
    if ! [[ -n "${_BL_CONST["PATH_SOURCE_$SCOPE"]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_SOURCE_$SCOPE]"
        return 2
    elif ! [[ -f "$ENVIRONMENT/${_BL_CONST["PATH_SOURCE_$SCOPE"]}" ]]; then
        bl_log "FATAL_NO_FILE" "$ENVIRONMENT/${_BL_CONST[PATH_SOURCE_$SCOPE]}"
        return 3
    elif ! [[ -r "$ENVIRONMENT/${_BL_CONST["PATH_SOURCE_$SCOPE"]}" &&
              -w "$ENVIRONMENT/${_BL_CONST["PATH_SOURCE_$SCOPE"]}" ]]; then
        bl_log "FATAL_NO_PERM" "$ENVIRONMENT/${_BL_CONST["PATH_SOURCE_$SCOPE"]}"
        return 4
    fi
    
    local -r SOURCE_FILE="$ENVIRONMENT/${_BL_CONST["PATH_SOURCE_$SCOPE"]}"

    local -a LINES
    bl_file_read_lines "$SOURCE_FILE" LINES || return 5

    local -i i
    for (( i = 0; i < size; i++ )); do

        local -a definition
        _bl_source_build_definition \
            "${KINDS[i]}" "${NAMES[i]}" "${SOURCES[i]}" definition || return 6

        starts_[i]=${#LINES[@]}
        LINES+=("${definition[@]}")
        ends_[i]=$(( ${#LINES[@]} - 1 ))
    done
    
    bl_file_write_atomic LINES "$SOURCE_FILE" || return 7
}

# Comment
_bl_source_build_definition() {

    local -r KIND="$1"
    local -r NAME="$2"
    local -r SOURCE="$3"
    local -n definition_=$4
    
    if ! [[ -n "${_BL_CONST[SCHEMA_KIND_ALIAS]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEMA_KIND_ALIAS]"
        return 1
    elif ! [[ -n "${_BL_CONST[SCHEMA_KIND_FUNCTION]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEMA_KIND_FUNCTION]"
        return 1
    elif ! [[ -n "${_BL_CONST[SCHEMA_KIND_VARIABLE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEMA_KIND_VARIABLE]"
        return 1
    fi
    
    case "$KIND" in
        "${_BL_CONST[SCHEMA_KIND_ALIAS]}")

            if ! mapfile -t definition_ <<< "$SOURCE"; then
                bl_log_debug "FATAL_EXTERNAL" "mapfile -t definition_ <<< $SOURCE"
                return 1
            fi
            definition_[0]="alias $NAME='${definition_[0]}"
            definition_[-1]="${definition_[-1]}'"
            ;;

        "${_BL_CONST[SCHEMA_KIND_FUNCTION]}")
            
            if ! mapfile -t definition_ <<< "$SOURCE"; then
                bl_log_debug "FATAL_EXTERNAL" "mapfile -t definition_ <<< $SOURCE"
                return 1
            fi
            definition_=("$NAME() {" "${definition_[@]}" "}")
            ;;
            
        "${_BL_CONST[SCHEMA_KIND_VARIABLE]}")
            
            if ! mapfile -t definition_ <<< "$SOURCE"; then
                bl_log_debug "FATAL_EXTERNAL" "mapfile -t definition_ <<< $SOURCE"
                return 1
            fi
            definition_[0]="$NAME='${definition_[0]}"
            definition_[-1]="${definition_[-1]}'"
            ;;
    esac
}