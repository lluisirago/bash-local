#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file add.bash
#
# @brief Internal implementation of `bl-add` CLI function.

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public funtions
#
# Functions in this section are intended to be called by CLI module.

# @description Resolves required settings and dispatches to other functions if
# necessary.
#
# Side effects:
# - Executes other CLI functions.
#
# @arg $1 string Reference to environment setting.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related error (logged).
# @exitcode 3 Success, dispatched function performed a terminal operation,
#             meaning no further execution is expected after its completion.
bl_add_take_in() {

    local version
    bl_cli_resolve VERSION version || return
    if [[ $version == true ]]; then
        bl-version || return # Should be bl_version_main
        return 3
    fi
    
    local help
    bl_cli_resolve HELP help || return
    if [[ $help == true ]]; then
        bl-help "${_BL_CONST[COMMAND_ADD]}" || return # Should be bl_help_main
        return 3
    fi

    local -n env_=$1
    bl_cli_resolve ENV env_ || return

    local init
    bl_cli_resolve INIT init || return
    if [[ $init == true ]]; then
        bl-init "$env_" || return # Should be bl_init_main
    fi
}

# @description Extracts element traits and validates them, argument by argument.
# Then adds all valid elements into the given environment.
#
# Two elements cannot have the same name.
#
# When invalid elements are processed, execution continues or not depending on
# atomic setting.
#
# Stdin acts as source for one element defined with `-`.
#
# @arg $1 string Atomic setting.
# @arg $2 string Environment setting.
# @arg $3 string Force setting.
# @arg $4 string Stdin.
# @arg $5 string Constant reference to argumments array.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related error (logged).
bl_add_main() {

    local -r ENV="$1"
    local -r STDIN="$2"
    local -rn ARGUMENTS=$3

    local atomic
    bl_cli_resolve ATOMIC atomic || return

    local force
    bl_cli_resolve FORCE force || return # ToDo

    local -a scopes kinds names source_types sources

    local stdin_used=false
    local atomic_failed=false

    local argument
    for argument in "${ARGUMENTS[@]}"; do
        
        _bl_add_process_argument "$argument" "$ENV" "$STDIN" \
            scopes kinds names source_types sources stdin_used
        case $? in
            1) return 1;;
            2) return 2;;
            3) [[ $atomic == true ]] && atomic_failed=true;;
        esac
    done

    [[ $atomic_failed == true ]] && { bl_log "FATAL_ATOMIC_FAILED"; return 2; }
    [[ $stdin_used == false && -n "$STDIN" ]] && bl_log "WARN_IGNORING_STDIN"

    _bl_add_resolve_editor "$EDITOR" scopes kinds names source_types sources || return
    _bl_add_elements "$ENV" scopes kinds names sources || return
    bl_core_update
    _bl_add_summarize "${#names[@]}" "${#ARGUMENTS[@]}" || return
}


# MARK: Private
# -----------------------------------------------------------------------------
# @section Private funtions
#
# Functions in this section are not intended to be called by other modules.

# @description Processes an argument by extracting its traits and appending
# them into given arrays if valid.
#
# Stdin acts as source for element if defined with `-`.
#
# @arg $1 string Argument.
# @arg $2 string Environment.
# @arg $3 string Stdin.
# @arg $4 array Reference to scopes array.
# @arg $5 array Reference to kinds array.
# @arg $6 array Reference to names array.
# @arg $7 array Reference to source types array.
# @arg $8 array Reference to sources array.
# @arg $9 string Reference to stdin flag.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related fatal error (logged).
# @exitcode 3 User-related error (logged).
_bl_add_process_argument() {

    local -r ARGUMENT="$1"
    local -r ENV="$2"
    local -r STDIN="$3"
    local -n scopes_=$4
    local -n kinds_=$5
    local -n names_=$6
    local -n source_types_=$7
    local -n sources_=$8
    local -n stdin_used_=$9

    if ! [[ -n "${_BL_CONST[ADD_ARGUMENT_REGEX]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_ARGUMENT_REGEX]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_FILE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_FILE]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_STDIN]"
        return 1
    fi

    if ! [[ $ARGUMENT =~ ${_BL_CONST[ADD_ARGUMENT_REGEX]} ]]; then
        bl_log "USAGE_INVALID_ARG_FORMAT" "$ARGUMENT"
        return 2
    fi

    local scope kind name source_type source
    _bl_add_extract "$ARGUMENT" scope kind name source_type source || return
    _bl_add_handle_conflicts "$ENV" "$name" names_ || return
    _bl_add_validate \
        "$scope" "$kind" "$name" "$source_type" "$source" "$STDIN" || return
    
    if [[ $source_type == "${_BL_CONST[ADD_SOURCE_TYPE_FILE]}" ]]; then
        _bl_add_resolve_file source_type source || return
    elif [[ $source_type == "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]}" ]]; then
        _bl_add_resolve_stdin "$STDIN" source_type source stdin_used_ || return
    fi

    scopes_+=("$scope")
    kinds_+=("$kind")
    names_+=("$name")
    source_types_+=("$source_type")
    sources_+=("$source")
}

# MARK: Extract
# -----------------------------------------------------------------------------
# @section Argument extraction
#
# Functions in this section extract traits from given argument.

# @description Extracts traits from an argument.
#
# Argument should have format defined in `_BL_CONST[ADD_ARGUMENT_REGEX]`.
#
# @arg $1 string Argument.
# @arg $2 string Reference to scope.
# @arg $3 string Reference to kind.
# @arg $4 string Reference to name.
# @arg $5 string Reference to source type.
# @arg $6 string Reference to source.
#
# @exitcode 0 Success.
# @exitcode 1 Extraction failed (logged in debug).
_bl_add_extract() {

    local -r ARGUMENT="$1"
    local -n scope_=$2
    local -n kind_=$3
    local -n name_=$4
    local -n source_type_=$5
    local -n source_=$6

    local left right
    if [[ $ARGUMENT == *=* ]]; then

        left="${ARGUMENT%%=*}"
        right=${ARGUMENT:${#left}}
    else
        left="$ARGUMENT"
        right=""
    fi

    _bl_add_extract_left "$left" scope_ kind_ name_ || return
    _bl_add_extract_right "$right" source_type_ source_ || return
}

# @description Extracts scope, kind and name from left side of argument.
#
# Left side should have one of following formats:
#  - <scope>:<kind>:<name>
#  - <kind>:<name>
#  - <name>
#
# @arg $1 string Left side of argument.
# @arg $2 string Reference to scope.
# @arg $3 string Reference to kind.
# @arg $4 string Reference to name.
#
# @exitcode 0 Success.
# @exitcode 1 Missing variable (logged in debug).
_bl_add_extract_left() {

    local -r LEFT="$1"
    local -n scope__=$2
    local -n kind__=$3
    local -n name__=$4

    if ! [[ -n "${_BL_CONST[SCHEMA_SCOPE_LOCAL]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEME_SCOPE_LOCAL]"
        return 1
    elif ! [[ -n "${_BL_CONST[SCHEMA_SCOPE_SCOPED]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEME_SCOPE_SCOPED]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_DEFAULT_SCOPE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_DEFAULT_SCOPE]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_DEFAULT_KIND]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_DEFAULT_KIND]"
        return 1
    fi

    case "$LEFT" in

        *:*:*)
            local -r TMP=${LEFT#*:}
            scope__=${LEFT%%:*}
            kind__=${TMP%%:*}
            name__=${TMP#*:}
            ;;
        *:*)
            local first
            first=${LEFT%%:*}

            scope__="${_BL_CONST[ADD_DEFAULT_SCOPE]}"
            kind__="$first"

            name__=${LEFT#*:}
            ;;
        *)
            scope__="${_BL_CONST[ADD_DEFAULT_SCOPE]}"
            kind__="${_BL_CONST[ADD_DEFAULT_KIND]}"
            name__=$LEFT
            ;;
    esac
}

# @description Extracts source type and source from right side of argument.
#
# Right side should have one of following formats:
#  - ''
#  - '-'
#  - '@<filepath>'
#  - '<value>'
#
# @arg $1 string Right side of argument.
# @arg $2 string Reference to source type.
# @arg $3 string Reference to source.
#
# @exitcode 0 Success.
# @exitcode 1 Missing variable (logged in debug).
_bl_add_extract_right() {

    local -r RIGHT="$1"
    local -n source_type__=$2
    local -n source__=$3

    if ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_EDITOR]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_STDIN]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_FILE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_FILE]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_INLINE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_INLINE]"
        return 1
    fi

    case "$RIGHT" in

        "")
            source_type__="${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]}"
            source__=""
            ;;
        =-)
            source_type__="${_BL_CONST[ADD_SOURCE_TYPE_STDIN]}"
            source__=""
            ;;
        =@*)
            source_type__="${_BL_CONST[ADD_SOURCE_TYPE_FILE]}"
            source__="${RIGHT#=@}"
            ;;
        =*)
            source_type__="${_BL_CONST[ADD_SOURCE_TYPE_INLINE]}"
            source__="${RIGHT#=}"
            ;;
    esac
}


# MARK: Conflicts
# -----------------------------------------------------------------------------
# @section Name conflicts handling
#
# Functions in this section handle name conflicts.

# @description Checks for a name conflict in given array of elements to be added
# and in target environment.
#
# @arg $1 string Environment.
# @arg $2 string Element name.
# @arg $3 array Constant reference to element names array.
#
# @exitcode 0 No name conflict.
# @exitcode 2 Argument conflict (logged).
# @exitcode 3 Environment conflict (logged).
_bl_add_handle_conflicts() {

    local -r ENV="$1"
    local -r NAME="$2"
    local -rn NAMES=$3
    
    if _bl_add_argument_conflict "$NAME" NAMES; then
        bl_log "FATAL_DUPLICATE" "$NAME"
        return 2
    fi
     
    if _bl_add_environment_conflict "$NAME" "$ENV"; then
        bl_log "ERROR_ALREADY_EXISTS" "$NAME" "$ENV"
        return 3
    fi
}

# @description Checks whether an element with given name already exists in given
# array of elements to be added.
#
# @arg $1 string Element name.
# @arg $2 array Constant reference to element names array.
#
# @exitcode 0 An element with the given name is about to exist.
# @exitcode 1 No name conflict.
_bl_add_argument_conflict() {

    local -r NAME="$1"
    local -rn NAMES_=$2

    local name
    for name in "${NAMES_[@]}"; do
        [[ $NAME == "$name" ]] && return 0
    done
    return 1
}

# @description Checks whether an element with given name already exists in
# target environment.
#
# @arg $1 string Element name.
# @arg $2 string Environment.
#
# @exitcode 0 An element with the given name exists.
# @exitcode 1 No name conflict.
_bl_add_environment_conflict() {

    local -r NAME="$1"
    local -r ENV="$2"
    
    local -a name_array=("$NAME")
    local -a linenos scopes kinds starts ends

    bl_manifest_collect_traits_by_name "$ENV" name_array \
        linenos scopes kinds starts ends || return 1

    [[ -n ${linenos[0]:-} ]] && return 0 || return 1
}


# MARK: Validate
# -----------------------------------------------------------------------------
# @section Element traits validators
#
# Functions in this section validate element traits.

# @description Validates element traits according to this rules:
# - Scope must be one of supported scopes.
# - Kind must be one of supported kinds.
# - Name must follow bash syntax.
# - Source type must be one of supported source types.
# - Source must follow bash syntax.
#
# @arg $1 string Scope.
# @arg $2 string Kind.
# @arg $3 string Name.
# @arg $4 string Source type.
# @arg $5 string Source.
# @arg $6 string Stdin.
#
# @exitcode 0 Success
# @exitcode 1 Internal error (logged in debug).
# @exitcode 3 User-related error(s) (logged).
_bl_add_validate() {

    local -r SCOPE="$1"
    local -r KIND="$2"
    local -r NAME="$3"
    local -r SOURCE_TYPE="$4"
    local -r SOURCE="$5"
    local -r STDIN="$6"

    local -a errors firsts seconds

    _bl_add_validate_scope "$SCOPE"
    case $? in
        1) return 1;;
        2)
            errors+=("ERROR_INVALID_SCOPE")
            firsts+=("$SCOPE")
            seconds+=("")
            ;;
    esac

    _bl_add_validate_kind "$KIND"
    case $? in
        1) return 1;;
        2)
            errors+=("ERROR_INVALID_KIND")
            firsts+=("$KIND")
            seconds+=("")
            ;;
    esac

    _bl_add_validate_name "$KIND" "$NAME"
    case $? in
        1) return 1;;
        2)
            errors+=("ERROR_INVALID_NAME")
            firsts+=("")
            seconds+=("")
            ;;
    esac
    
    local source_error
    _bl_add_validate_source "$KIND" "$SOURCE_TYPE" "$SOURCE" "$STDIN" source_error
    case $? in
        1) return 1;;
        2)
            errors+=("ERROR_INVALID_INLINE_DEFINITION")
            firsts+=("$source_error")
            seconds+=("")
            ;;
        3)
            errors+=("ERROR_NOT_FILE")
            firsts+=("$(realpath "$SOURCE")")
            seconds+=("")
            ;;
        4)
            errors+=("ERROR_INVALID_FILE_DEFINITION")
            firsts+=("$(realpath "$SOURCE")")
            seconds+=("$source_error")
            ;;
        5)
            errors+=("ERROR_NO_STDIN")
            firsts+=("")
            seconds+=("")
            ;;
        6)
            errors+=("ERROR_INVALID_STDIN_DEFINITION")
            firsts+=("$source_error")
            seconds+=("")
            ;;
        7)
            bl_log_debug "FATAL_ADD_VALIDATE_SOURCE_UNKNOWN_SOURCE_TYPE" \
                "$NAME" "$SOURCE_TYPE"
            return 1
    esac
    
    if (( ${#errors[@]} > 0 )); then
        _bl_add_report_errors "$NAME" errors firsts seconds
        return 3
    else
        return 0
    fi
}

# @description Validates an element scoped. Must be one of supported scopes.
#
# @arg $1 string Scope.
#
# @exitcode 0 Success.
# @exitcode 2 Invalid scope.
_bl_add_validate_scope() {

    local -r SCOPE="$1"
    for key in "${!_BL_CONST[@]}"; do

        [[ $key == "SCHEMA_SCOPE_"* ]] || continue
        [[ $SCOPE == "${_BL_CONST["$key"]}" ]] && return 0
    done
    return 2
}

# @description Validates an element kind. Must be one of supported kinds.
#
# @arg $1 string Kind.
#
# @exitcode 0 Success.
# @exitcode 2 Invalid kind.
_bl_add_validate_kind() {

    local -r KIND="$1"
    for key in "${!_BL_CONST[@]}"; do

        [[ $key == "SCHEMA_KIND_"* ]] || continue
        [[ $KIND == "${_BL_CONST["$key"]}" ]] && return 0
    done
    return 2
}

# @description Validates an element name. Must follow bash syntax.
#
# @arg $1 string Kind.
# @arg $2 string Name.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug)
# @exitcode 2 Invalid name format.
_bl_add_validate_name() {

    local -r KIND="$1"
    local -r NAME="$2"

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
            bash -c 'alias "$1=" >/dev/null' _ "$NAME" 2>/dev/null || return 2
            ;;
        "${_BL_CONST[SCHEMA_KIND_FUNCTION]}")
            [[ $NAME =~ ${_BL_CONST[ADD_SHELL_ID_REGEX]} ]] || return 2
            ;;
        "${_BL_CONST[SCHEMA_KIND_VARIABLE]}")
            [[ $NAME =~ ${_BL_CONST[ADD_SHELL_ID_REGEX]} ]] || return 2
            ;;
    esac
}

# @description Validates an element source. Validation is performed using
# `bash -n` tool. If source is a file, both file existence and file content are
# checked.
#
# In case of an error, it is given in a normalized format defined in
# `_bl_add_normalize_source_error`.
#
# @arg $1 string Kind.
# @arg $2 string Source type.
# @arg $3 string Source.
# @arg $4 string Stdin.
# @arg $5 string Reference to error.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 Invalid inline definition.
# @exitcode 3 Invalid file.
# @exitcode 4 Invalid definition in file.
# @exitcode 5 Empty stdin.
# @exitcode 6 Invalid definition in stdin.
# @exitcode 7 Unknown source type.
_bl_add_validate_source() {

    local -r KIND="$1"
    local -r SOURCE_TYPE="$2"
    local -r SOURCE="$3"
    local -r STDIN="$4"
    local -n source_error_=$5
    
    source_error_=""

    if ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_INLINE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_INLINE]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_FILE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_FILE]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_EDITOR]"
        return 1
    elif ! [[ -n "${_BL_CONST[SCHEMA_KIND_ALIAS]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEMA_KIND_ALIAS]"
        return 1
    elif ! [[ -n "${_BL_CONST[SCHEMA_KIND_FUNCTION]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEMA_KIND_FUNCTION]"
        return 1
    elif ! [[ -n "${_BL_CONST[SCHEMA_KIND_VARIABLE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SCHEMA_KIND_VARIABLE]"
        return 1
    fi

    if [[ $SOURCE_TYPE == "${_BL_CONST[ADD_SOURCE_TYPE_INLINE]}" ]]; then

        case "$KIND" in
            "${_BL_CONST[SCHEMA_KIND_ALIAS]}") ;;
            "${_BL_CONST[SCHEMA_KIND_FUNCTION]}")

                source_error_=$(bash -n -c "_() {
                    $SOURCE
                    }" 2>&1)
                local -r STATUS=$?

                if (( STATUS != 0 )); then
                    _bl_add_normalize_source_error source_error_
                    return 2
                fi
                ;;
            "${_BL_CONST[SCHEMA_KIND_VARIABLE]}") ;;
        esac

    elif [[ $SOURCE_TYPE == "${_BL_CONST[ADD_SOURCE_TYPE_FILE]}" ]]; then
        
        [[ -f "$SOURCE" ]] || return 3

        case "$KIND" in
            "${_BL_CONST[SCHEMA_KIND_ALIAS]}") ;;
            "${_BL_CONST[SCHEMA_KIND_FUNCTION]}")
                
                source_error_=$(
                    {
                        printf '_() {\n'
                        cat "$SOURCE"
                        printf '\n}\n'
                    } | bash -n 2>&1
                )
                local -r STATUS=$?
                
                if (( STATUS != 0 )); then
                    _bl_add_normalize_source_error source_error_
                    return 4
                fi
                ;;
            "${_BL_CONST[SCHEMA_KIND_VARIABLE]}") ;;
        esac

    elif [[ $SOURCE_TYPE == "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]}" ]]; then
        
        [[ -n "$STDIN" ]] || return 5

        case "$KIND" in
            "${_BL_CONST[SCHEMA_KIND_ALIAS]}") ;;
            "${_BL_CONST[SCHEMA_KIND_FUNCTION]}")

                source_error_=$(bash -n -c "_() {
                    $STDIN
                    }" 2>&1)
                local -r STATUS=$?

                if (( STATUS != 0 )); then
                    _bl_add_normalize_source_error source_error_
                    return 6
                fi
                ;;
            "${_BL_CONST[SCHEMA_KIND_VARIABLE]}") ;;
        esac

    elif [[ $SOURCE_TYPE == "${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]}" ]]; then
        true
    else
        return 7
    fi
}

# @description Reports collected errors in element validation by translating
# each one into a message and logging them as one error.
#
# @arg $1 string Name.
# @arg $2 array Constant reference to errors array.
# @arg $3 array Constant reference to first objects array.
# @arg $4 array Constant reference to second objects array.
#
# @exitcode 0 Success
_bl_add_report_errors() {

    local -r NAME="$1"
    local -rn ERRORS=$2
    local -rn FIRSTS=$3
    local -rn SECONDS=$4

    local error message output i
    for (( i = 0; i < ${#ERRORS[@]}; i++ )); do

        _bl_log_translate "${ERRORS[i]}" message "${FIRSTS[i]}" "${SECONDS[i]}"
        output+="$message"$'\n'""
    done

    _bl_add_normalize_error output
    bl_log "ERROR_INVALID_ELEMENT" "$NAME" "$output"
}

# @description Normalizes source error format by removing `bash: -c: ` and
# `bash: ` appearances, substracting 1 to error lines and applying general error
# normalization.
#
# @arg $1 string Reference to error.
#
# @exitcode 0 Success.
_bl_add_normalize_source_error () {

    local -n error=$1

    # Remove all 'bash: -c: ' and 'bash: ' appearances
    error=${error//bash: -c: /}
    error=${error//bash: }
    
    # Substract 1 to error lines
    new_error=""
    while IFS= read -r line; do

        if [[ $line =~ ^(.*line[[:space:]]+)([0-9]+)(:.*)$ ]]; then
            line="${BASH_REMATCH[1]}$((BASH_REMATCH[2]-1))${BASH_REMATCH[3]}"
        fi
        new_error+="$line"$'\n'

    done <<< "$error"
    error=${new_error%$'\n'}

    # Pretty-print
    _bl_add_normalize_error error
}

# @description Normalizes error format by removing last line break and indenting
# as follows:
# - Multiple-line error:
#     error1
#     error2
# - Single-line error: error1
#
# @arg $1 string Reference to error.
#
# @exitcode 0 Success.
_bl_add_normalize_error () {

    local -n error_=$1

    # Remove last line break
    error_=${error_%$'\n'}

    # Check if multiple-line error
    if [[ $error_ == *$'\n'* ]]; then
        
        # Add line break at beginning and indent with two spaces before each
        # line
        error_=$'\n'"  ${error_//$'\n'/$'\n  '}"
    else
        # Indent with one space
        error_=" $error_"
    fi
}


# MARK: File
# -----------------------------------------------------------------------------
# @section File resolution
#
# Functions in this section resolves file source.

# @description Resolves a file source by replacing it with the file content as
# an inline source.
#
# Source MUST refer to an existing file with
# reading permissions.
#
# @arg $1 string Reference to source type.
# @arg $2 string Reference to source.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
_bl_add_resolve_file() {

    local -n source_type_=$1
    local -n source_=$2

    if [[ $source_type_ != "${_BL_CONST[ADD_SOURCE_TYPE_FILE]}" ]]; then
        bl_log_debug "FATAL_ADD_RESOLVE_STDIN_NOT_FILE"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_INLINE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_INLINE]"
        return 1
    fi

    source_type_="${_BL_CONST[ADD_SOURCE_TYPE_INLINE]}"
    source_=$(<"$source_")
}


# MARK: Stdin
# -----------------------------------------------------------------------------
# @section Stdin resolution
#
# Functions in this section resolves stdin source.

# @description Resolves a stdin source by replacing it with the stdin content as
# an inline source.
#
# Stdin may only be used once and must not be empty.
#
# @arg $1 string Stdin.
# @arg $2 string Reference to source type.
# @arg $3 string Reference to source.
# @arg $4 string Reference to stdin-used flag.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 Multiple stdin arguments (logged).
_bl_add_resolve_stdin() {

    local -r STDIN="$1"
    local -n source_type_=$2
    local -n source_=$3
    local -n stdin_used__=$4

    if [[ $source_type_ != "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]}" ]]; then
        bl_log_debug "FATAL_ADD_RESOLVE_STDIN_NOT_STDIN"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_INLINE]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_INLINE]"
        return 1
    elif [[ $stdin_used__ == true ]]; then
        bl_log "FATAL_MULTIPLE_STDIN"
        return 2
    fi

    source_type_="${_BL_CONST[ADD_SOURCE_TYPE_INLINE]}"
    source_="$STDIN"
    stdin_used__=true
}


# MARK: Editor
# -----------------------------------------------------------------------------
# @section Editor resolution
#
# Functions in this section resolves editor source.

_bl_add_resolve_editor() {

    local -r EDITOR="$1"
    local -rn SCOPES=$2
    local -rn KINDS=$3
    local -rn NAMES=$4
    local -rn SOURCE_TYPES=$5
    local -rn SOURCES=$6

    # Create a copy
    local -a scopes=("${SCOPES[@]}")
    local -a kinds=("${KINDS[@]}")
    local -a names=("${NAMES[@]}")
    local -a source_types=("${SOURCE_TYPES[@]}")
    local -a sources=("${SOURCES[@]}")

    _bl_add_filter_editor_elements \
        scopes kinds names source_types sources || return
    [[ ${#names[@]} -eq 0 ]] && return 0

    local tmp editor args
    _bl_add_create_editor_file \
        scopes kinds names source_types sources tmp || return
    bl_cli_resolve EDITOR editor || return
    _bl_add_get_editor_args "$editor" args || return
    "$editor" "${args[@]}" "$tmp"

    cat "$tmp"
    # Parse temp file

    # Set source types to inline and sources in refs
}

# @description Filters trait arrays to keep only editor elements traits.
#
# @arg $1 array Reference to scopes array.
# @arg $2 array Reference to kinds array.
# @arg $3 array Reference to names array.
# @arg $4 array Reference to source types array.
# @arg $5 array Reference to sources array.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
_bl_add_filter_editor_elements() {

    local -n scopes_=$1
    local -n kinds_=$2
    local -n names_=$3
    local -n source_types_=$4
    local -n sources_=$5

    local size=${#names_[@]}
    [[ size -ne 0 ]] || return 0

    # shellcheck disable=SC2056
    if (( size != ${#scopes_[@]} || size != ${#kinds_[@]}  ||
          size != ${#source_types_[@]} || size != ${#sources_[@]} )); then
        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_SOURCE_TYPE_EDITOR]"
        return 1
    fi

    local -a aux_scopes aux_kinds aux_names aux_source_types aux_sources
    local -i i
    for (( i = 0; i < ${#names_[@]}; i++ )); do

        if [[ ${source_types_[i]} == "${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]}" ]]; then
            
            aux_scopes+=("${scopes_[i]}")
            aux_kinds+=("${kinds_[i]}")
            aux_names+=("${names_[i]}")
            aux_source_types+=("${source_types_[i]}")
            aux_sources+=("${sources_[i]}")
        fi
    done

    scopes_=("${aux_scopes[@]}")
    kinds_=("${aux_kinds[@]}")
    names_=("${aux_names[@]}")
    source_types_=("${aux_source_types[@]}")
    sources_=("${aux_sources[@]}")
}

# @description Creates a temporary file with a template that will be edited by
# the user.
#
# @arg $1 array Constant reference to scopes array.
# @arg $2 array Constant reference to kinds array.
# @arg $3 array Constant reference to names array.
# @arg $4 array Constant reference to source types array.
# @arg $5 array Constant reference to sources array.
# @arg $6 string Reference to temporary file.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
_bl_add_create_editor_file() {

    local -rn SCOPES=$1
    local -rn KINDS=$2
    local -rn NAMES=$3
    local -rn SOURCE_TYPES=$4
    local -rn SOURCES=$5
    local -n tmp_=$6

    local template
    _bl_add_build_editor_template \
        SCOPES KINDS NAMES SOURCE_TYPES SOURCES template || return
    bl_file_create_tmp "/tmp" tmp_ || return
    _bl_add_trap_editor_return "$tmp_" || return
    bl_file_write "$tmp_" template || return
}

# @description Builds the editor template, starting with the header defined in
# _BL_CONST[ADD_EDITOR_TEMPLATE_HEADER]. Each element entry has the following
# format:
#
# <kind>:<name> <prompt_begin>
#
# <prompt_end>
#
# @arg $1 array Constant reference to scopes array.
# @arg $2 array Constant reference to kinds array.
# @arg $3 array Constant reference to names array.
# @arg $4 array Constant reference to source types array.
# @arg $5 array Constant reference to sources array.
# @arg $6 string Reference to template.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
_bl_add_build_editor_template() {

    local -rn SCOPES_=$1
    local -rn KINDS_=$2
    local -rn NAMES_=$3
    local -rn SOURCE_TYPES_=$4
    local -rn SOURCES_=$5
    local -n template_=$6

    template_=""

    local size=${#NAMES_[@]}
    [[ size -ne 0 ]] || return 0

    # shellcheck disable=SC2056
    if (( size != ${#SCOPES_[@]} || size != ${#KINDS_[@]}  ||
          size != ${#SOURCE_TYPES_[@]} || size != ${#SOURCES_[@]} )); then
        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_EDITOR_TEMPLATE_HEADER]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_EDITOR_TEMPLATE_HEADER]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_EDITOR_TEMPLATE_PROMPT_BEGIN]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_EDITOR_TEMPLATE_PROMPT_BEGIN]"
        return 1
    elif ! [[ -n "${_BL_CONST[ADD_EDITOR_TEMPLATE_PROMPT_END]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_EDITOR_TEMPLATE_PROMPT_END]"
        return 1
    fi

    template_="${_BL_CONST[ADD_EDITOR_TEMPLATE_HEADER]}"
    local begin="${_BL_CONST[ADD_EDITOR_TEMPLATE_PROMPT_BEGIN]}"
    local end="${_BL_CONST[ADD_EDITOR_TEMPLATE_PROMPT_END]}"

    local -i i
    for (( i = 0; i < ${#NAMES_[@]}; i++ )); do
        template_+=$'\n\n'"${KINDS_[i]}:${NAMES_[i]} $begin"$'\n\n'"$end"
    done
}

# @description Traps RETURN signal removing temporal file used for editor
# elements.
#
# @arg $1 string Temporal file path.
#
# @exitcode Return value trapped.
_bl_add_trap_editor_return() {

    local -r TMP="$1"

    local old_trap_
    old_trap_=$(trap -p RETURN)
    
    # shellcheck disable=SC2329
    cleanup_return() {

        local status=$?

        bl_run_external rm -rf -- "$TMP"
        trap - RETURN
        [[ -n "${old_trap_:-}" ]] && eval "$old_trap_"

        return "$status"
    }
    trap cleanup_return RETURN
}

# @description Gets argument needed for given editor, since some editors do not
# stop execution of caller function until exited.
#
# An array is used instead of a string because, unlike an empty array, an empty
# string is passed as an argument to the editor.
#
# @arg $1 string Editor.
# @arg $2 Reference to args array.
#
# @exitcode 0 Success.
_bl_add_get_editor_args() {

    local -r EDITOR="$1"
    local -n args_=$2
    
    if [[ -n "${_BL_CONST["ARG_OF_$EDITOR"]:-}" ]]; then
        args_=("${_BL_CONST["ARG_OF_$EDITOR"]}")
    else
        args_=()
    fi
}


# MARK: Add
# -----------------------------------------------------------------------------
# @section Add elements into environment
#
# Functions in this section add the elements into manifest and source files.

# @description Add elements to an environment by writing into manifest and
# source files.
#
# @arg $1 string Environment.
# @arg $2 array Constant reference to scopes array.
# @arg $3 array Constant reference to kinds array.
# @arg $4 array Constant reference to names array.
# @arg $5 array Constant reference to sources array.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related error (logged).
_bl_add_elements() {

    local -r ENV="$1"
    local -rn SCOPES=$2
    local -rn KINDS=$3
    local -rn NAMES=$4
    local -rn SOURCES=$5

    local size=${#NAMES[@]}
    [[ size -ne 0 ]] || return 0

    # shellcheck disable=SC2056
    if (( size != ${#SCOPES[@]} || size != ${#KINDS[@]} ||
          size != ${#SOURCES[@]} )); then

        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi

    local -a starts ends

    bl_source_append "$ENV" NAMES SCOPES KINDS SOURCES starts ends || return
    bl_manifest_append "$ENV" NAMES SCOPES KINDS starts ends || return
}


# MARK: Summary
# -----------------------------------------------------------------------------
# @section Summary log
#
# Functions in this section log a summary.

# @description Logs a summary of added elements.
#
# - All elements added: no summary.
# - Some elements added: `Added n of m elements`.
# - No elements added: `No elements were added`.
#
# @arg $1 integer Number of added elements.
# @arg $2 integer Number of initially requested elements.
#
# @exitcode 0 Success.
_bl_add_summarize() {

    local -ri NUM_ADDED="$1"
    local -ri NUM_REQUESTED="$2"

    local -ri NUM_FAILED=$(( NUM_REQUESTED - NUM_ADDED ))
    
    if (( NUM_FAILED > 0 && NUM_ADDED > 0 )); then
        bl_log "INFO_ADD_SUMMARY_SOME" "$NUM_ADDED" "$NUM_REQUESTED"
    elif (( NUM_FAILED > 0 && NUM_ADDED == 0 )); then
        bl_log "INFO_ADD_SUMMARY_NONE"
    fi

    return 0
}