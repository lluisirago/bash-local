#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file source.bash
#
# @brief Source files manager.
# @description Implements functions responsible for accessing source files.
# They collect, append and remove rows from/to the files.

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public functions
#
# @description Functions in this sections are intended to be called by other
# modules.

# @description Appends elements to source files. Inserts each element at the end
# of its corresponding file.
#
# Starting and ending lines will be ordered by element position in arrays.
#
# If no elements given, the function is a no-op.
#
# Side effects:
# - Reads and writes source files.
#
# @arg $1 string Environment path (without trailing '/').
# @arg $2 array Constant reference to names array.
# @arg $3 array Constant reference to scopes array.
# @arg $4 array Constant reference to kinds array.
# @arg $5 array Constant reference to sources array.
# @arg $6 array Reference to starting lines array.
# @arg $7 array Reference to ending lines array.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related error (logged).
bl_source_append() {
    
    local -r ENV="$1"
    local -rn NAMES_=$2
    local -rn SCOPES_=$3
    local -rn KINDS_=$4
    local -rn SOURCES_=$5
    local -n starts_=$6
    local -n ends_=$7

    local size=${#NAMES_[@]}
    [[ size -ne 0 ]] || return 0

    # shellcheck disable=SC2056
    if (( size != ${#SCOPES_[@]} || size != ${#KINDS_[@]} || 
          size != ${#SOURCES_[@]} )); then

        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi
    
    if ! [[ -n "${_BL_CONST[PATH_SOURCE_LOCAL]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_SOURCE_LOCAL]"
        return 1
    elif ! [[ -n "${_BL_CONST[PATH_SOURCE_SCOPED]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_SOURCE_SCOPED]"
        return 1
    elif ! [[ -f "$ENV/${_BL_CONST[PATH_SOURCE_LOCAL]}" ]]; then
        bl_log "FATAL_NO_FILE" "$ENV/${_BL_CONST[PATH_SOURCE_LOCAL]}"
        return 2
    elif ! [[ -f "$ENV/${_BL_CONST[PATH_SOURCE_SCOPED]}" ]]; then
        bl_log "FATAL_NO_FILE" "$ENV/${_BL_CONST[PATH_SOURCE_SCOPED]}"
        return 2
    elif ! [[ -r "$ENV/${_BL_CONST[PATH_SOURCE_LOCAL]}" &&
              -w "$ENV/${_BL_CONST[PATH_SOURCE_LOCAL]}" ]]; then
        bl_log "FATAL_NO_PERM" "$ENV/${_BL_CONST[PATH_SOURCE_LOCAL]}"
        return 2
    elif ! [[ -r "$ENV/${_BL_CONST[PATH_SOURCE_SCOPED]}" &&
              -w "$ENV/${_BL_CONST[PATH_SOURCE_SCOPED]}" ]]; then
        bl_log "FATAL_NO_PERM" "$ENV/${_BL_CONST[PATH_SOURCE_SCOPED]}"
        return 2
    fi
    
    local -r LOCAL_FILE="$ENV/${_BL_CONST[PATH_SOURCE_LOCAL]}"
    local -r SCOPED_FILE="$ENV/${_BL_CONST[PATH_SOURCE_SCOPED]}"

    local -a LOCAL_LINES SCOPED_LINES
    bl_file_read_lines "$LOCAL_FILE" LOCAL_LINES || return
    bl_file_read_lines "$SCOPED_FILE" SCOPED_LINES || return

    local -i i
    for (( i = 0; i < size; i++ )); do

        local -a definition
        _bl_source_build_definition \
            "${KINDS_[i]}" "${NAMES_[i]}" "${SOURCES_[i]}" definition || return

        case "${SCOPES_[i]}" in

            "${_BL_CONST[SCHEMA_SCOPE_LOCAL]}")
                
                starts_[i]=${#LOCAL_LINES[@]}
                LOCAL_LINES+=("${definition[@]}")
                ends_[i]=$(( ${#LOCAL_LINES[@]} - 1 ))
                ;;

            "${_BL_CONST[SCHEMA_SCOPE_SCOPED]}")
                
                starts_[i]=${#SCOPED_LINES[@]}
                SCOPED_LINES+=("${definition[@]}")
                ends_[i]=$(( ${#SCOPED_LINES[@]} - 1 ))
                ;;
        esac
    done

    bl_file_write_atomic "$LOCAL_FILE" LOCAL_LINES || return
    bl_file_write_atomic "$SCOPED_FILE" SCOPED_LINES || return
}

# @description Builds the definition for the given element. Resulting Format
# depends on element type:
# - Alias: alias <name>='<definition>'
# - Function:
# <name> () {
#   <definition>
# }
# - Variable: <name>='<definition>'
#
# Note that <definition> preserves newline characters as '\n' escape sequences,
# as provided by the user.
#
# Definition is an array where each element represents one line of the element's
# definition.
#
# @arg $1 string Kind (as defined in '_BL_CONST').
# @arg $2 string Name.
# @arg $3 string Source.
# @arg $4 array Reference to definition array.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
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