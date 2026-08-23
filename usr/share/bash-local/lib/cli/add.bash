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

# @description Resolves settings and dispatches to other functions when
# necessary.
#
# Side effects:
# - Executes other CLI functions.
#
# @arg $1 string Reference to atomic setting.
# @arg $2 string Reference to environment setting.
# @arg $3 string Reference to force setting.
# @arg $4 string Reference to help setting.
# @arg $5 string Reference to init setting.
# @arg $6 string Reference to verbose setting.
# @arg $7 string Reference to version setting.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related error (logged).
# @exitcode 3 Success, dispatched function performed a terminal operation,
#             meaning no further execution is expected after its completion.
bl_add_take_in() {

    local -n version_=$7
    _bl_cli_resolve VERSION version_ || return
    if [[ $version_ == true ]]; then
        bl-version || return # Should be bl_version_main
        return 3
    fi
    
    local -n help_=$4
    _bl_cli_resolve HELP help_ || return
    if [[ $help_ == true ]]; then
        bl-help "${_BL_CONST[COMMAND_ADD]}" || return # Should be bl_help_main
        return 3
    fi

    local -n env_=$2
    _bl_cli_resolve ENV env_ || return

    local -n init_=$5
    _bl_cli_resolve INIT init_ || return
    if [[ $init_ == true ]]; then
        bl-init "$env_" || return
    fi

    local -n atomic_=$1
    _bl_cli_resolve ATOMIC atomic_ || return

    local -n force_=$3
    _bl_cli_resolve FORCE force_ || return

    local -n verbose_=$6
    _bl_cli_resolve VERBOSE verbose_ || return
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

    local -r ATOMIC="$1"
    local -r ENV="$2"
    local -r FORCE="$3" #ToDo
    local -r STDIN="$4"
    local -rn ARGUMENTS=$5

    local -a scopes kinds names source_types sources

    local stdin_used=false
    local atomic_failed=false

    local argument
    for argument in "${ARGUMENTS[@]}"; do
        
        _bl_add_process_argument "$argument" \
            scopes kinds names source_types sources stdin_used
        case $? in
            1) return 1;;
            2) return 2;;
            3)
                if [[ $ATOMIC == true ]]; then
                    atomic_failed=true
                else
                    continue
                fi
                ;;
        esac
    done

    [[ $atomic_failed == true ]] && { bl_log "FATAL_ATOMIC_FAILED"; return 2; }
    [[ $stdin_used == false && -n "$STDIN" ]] && bl_log "WARN_IGNORING_STDIN"

    _bl_add_resolve_editor scopes kinds names source_types sources || return

    # Add elements into environment

    _bl_add_summarize "${#names[@]}" "${#ARGUMENTS[@]}"
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
# @arg $2 array Reference to scopes array.
# @arg $3 array Reference to kinds array.
# @arg $4 array Reference to names array.
# @arg $5 array Reference to source types array.
# @arg $6 array Reference to sources array.
# @arg $7 string Reference to stdin flag.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 User-related fatal error (logged).
# @exitcode 3 User-related error (logged).
_bl_add_process_argument() {

    local -r ARGUMENT="$1"
    local -n scopes_=$2
    local -n kinds_=$3
    local -n names_=$4
    local -n source_types_=$5
    local -n sources_=$6
    local -n stdin_used_=$7

    if ! [[ -n "${_BL_CONST[ADD_ARGUMENT_REGEX]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[ADD_ARGUMENT_REGEX]"
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

    if [[ $source_type == "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]}" ]]; then
        _bl_add_resolve_stdin "$STDIN" source_type source stdin_used_ || return
    fi

    _bl_add_handle_conflicts "$ENV" "$name" names_ || return
    _bl_add_validate "$scope" "$kind" "$name" "$source_type" "$source" || return
    
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


# MARK: Stdin
# -----------------------------------------------------------------------------
# @section Stdin resolution
#
# Functions in this section resolves stdin source.

# @description Resolves a stdin source by replacing it with the stdin content as
# an inline source.
#
# Source type must be stdin. Stdin may only be used once and must not be empty.
#
# @arg $1 string stdin.
# @arg $2 string Reference to source type.
# @arg $3 string Reference to source.
# @arg $4 string Reference to stdin-used flag.
#
# @exitcode 0 Success.
# @exitcode 1 Source type is not stdin (logged in debug).
# @exitcode 2 Multiple stdin arguments (logged).
# @exitcode 3 Empty stdin (logged).
_bl_add_resolve_stdin() {

    local -r STDIN="$1"
    local -n source_type_=$2
    local -n source_=$3
    local -n stdin_used_=$4

    if [[ $source_type_ != "${_BL_CONST[ADD_SOURCE_TYPE_STDIN]}" ]]; then
        bl_log_debug "FATAL_ADD_RESOLVE_STDIN_NOT_STDIN"
        return 1
    elif [[ $stdin_used_ == true ]]; then
        bl_log "FATAL_MULTIPLE_STDIN"
        return 2
    elif [[ -z "$STDIN" ]]; then
        bl_log "ERROR_NO_STDIN"
        return 3
    fi

    source_type_="${_BL_CONST[ADD_SOURCE_TYPE_INLINE]}"
    source_="$STDIN"
    stdin_used_=true
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
#
# @exitcode 0 Success
# @exitcode 1 Internal error (logged in debug).
# @exitcode 3 User-related error/s (logged).
_bl_add_validate() {

    local -r SCOPE="$1"
    local -r KIND="$2"
    local -r NAME="$3"
    local -r SOURCE_TYPE="$4"
    local -r SOURCE="$5"

    local -a errors firsts seconds

    if ! _bl_add_validate_scope "$SCOPE"; then
        errors+=("ERROR_INVALID_SCOPE")
        firsts+=("$SCOPE")
        seconds+=("")
    fi

    if ! _bl_add_validate_kind "$KIND"; then
        errors+=("ERROR_INVALID_KIND")
        firsts+=("$KIND")
        seconds+=("")
    fi

    if ! _bl_add_validate_name "$KIND" "$NAME"; then
        errors+=("ERROR_INVALID_NAME")
        firsts+=("")
        seconds+=("")
    fi
    
    local source_error
    _bl_add_validate_source "$KIND" "$SOURCE_TYPE" "$SOURCE" source_error
    case $? in
        1)
            errors+=("ERROR_INVALID_INLINE_DEFINITION")
            firsts+=("$source_error")
            seconds+=("")
            ;;
        2)
            errors+=("ERROR_NOT_FILE")
            firsts+=("$(realpath "$SOURCE")")
            seconds+=("")
            ;;
        3)
            errors+=("ERROR_INVALID_FILE_DEFINITION")
            firsts+=("$(realpath "$SOURCE")")
            seconds+=("$source_error")
            ;;
        4)
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
# @exitcode 1 Invalid scope.
_bl_add_validate_scope() {

    local -r SCOPE="$1"
    for key in "${!_BL_CONST[@]}"; do

        [[ $key == "SCHEMA_SCOPE_"* ]] || continue
        [[ $SCOPE == "${_BL_CONST["$key"]}" ]] && return 0
    done
    return 1
}

# @description Validates an element kind. Must be one of supported kinds.
#
# @arg $1 string Kind.
#
# @exitcode 0 Success.
# @exitcode 1 Invalid kind.
_bl_add_validate_kind() {

    local -r KIND="$1"
    for key in "${!_BL_CONST[@]}"; do

        [[ $key == "SCHEMA_KIND_"* ]] || continue
        [[ $KIND == "${_BL_CONST["$key"]}" ]] && return 0
    done

    return 1
}

# @description Validates an element name. Must follow bash syntax.
#
# @arg $1 string Kind.
# @arg $2 string Name.
#
# @exitcode 0 Success.
# @exitcode 1 Invalid name format.
_bl_add_validate_name() {

    local -r KIND="$1"
    local -r NAME="$2"

    case "$KIND" in
        "${_BL_CONST[SCHEMA_KIND_ALIAS]}")
            bash -c 'alias "$1=" >/dev/null' _ "$NAME" 2>/dev/null || return 1
            ;;
        "${_BL_CONST[SCHEMA_KIND_FUNCTION]}")
            [[ $NAME =~ ${_BL_CONST[ADD_SHELL_ID_REGEX]} ]] || return 1
            ;;
        "${_BL_CONST[SCHEMA_KIND_VARIABLE]}")
            [[ $NAME =~ ${_BL_CONST[ADD_SHELL_ID_REGEX]} ]] || return 1
            ;;
    esac
}

# @description Validates an element source. Validation is performed using
# `bash -n` tool. If source is a file, both file existence and file content are
# checked.
#
# In case of an error, it is given in a normalized format as defined in
# `_bl_add_normalize_source_error`.
#
# @arg $1 string Kind.
# @arg $2 string Source type.
# @arg $3 string Source.
# @arg $4 string Reference to error.
#
# @exitcode 0 Success.
# @exitcode 1 Invalid inline definition.
# @exitcode 2 File does not exist.
# @exitcode 3 Invalid definition in file.
# @exitcode 4 Unknown source type.
_bl_add_validate_source() {

    local -r KIND="$1"
    local -r SOURCE_TYPE="$2"
    local -r SOURCE="$3"
    local -n source_error_=$4
    
    source_error_=""

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
                    return 1
                fi
                ;;
            "${_BL_CONST[SCHEMA_KIND_VARIABLE]}") ;;
        esac

    elif [[ $SOURCE_TYPE == "${_BL_CONST[ADD_SOURCE_TYPE_FILE]}" ]]; then
        
        [[ -f "$SOURCE" ]] || return 2
        
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
                    return 3
                fi
                ;;
            "${_BL_CONST[SCHEMA_KIND_VARIABLE]}") ;;
        esac
    elif [[ $SOURCE_TYPE == "${_BL_CONST[ADD_SOURCE_TYPE_EDITOR]}" ]]; then
        true
    else
        return 4
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
# @exitcode 1 Log error.
_bl_add_report_errors() {

    local -r NAME="$1"
    local -rn ERRORS=$2
    local -rn FIRSTS=$3
    local -rn SECONDS=$4

    local error message output i
    for (( i=0; i<${#ERRORS[@]}; i++ )); do

        _bl_log_translate "${ERRORS[i]}" message "${FIRSTS[i]}" "${SECONDS[i]}"
        output+="$message"$'\n'""
    done

    _bl_add_normalize_error output
    bl_log "ERROR_INVALID_ELEMENT" "$NAME" "$output" || return 1
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

    # Remove all bash: -c: and bash: appearances
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


# MARK: Editor
# -----------------------------------------------------------------------------
# @section Editor resolution
#
# Functions in this section resolves editor source.

_bl_add_resolve_editor() {

    local -rn scopes_=$1
    local -rn kinds_=$2
    local -rn names_=$3
    local -rn source_types_=$4
    local -rn sources_=$5

    local -a scopes=("${scopes_[@]}")
    local -a kinds=("${kinds_[@]}")
    local -a names=("${names_[@]}")
    local -a source_types=("${source_types_[@]}")
    local -a sources=("${sources_[@]}")

    # Get EDITOR source type elements

    local -r TMP=$(mktemp)
    printf "Editor file: %s\nContent:\n" "$TMP"

    _bl_add_trap_editor_return "$TMP"

    # Write comments and sections in file
    cat >"$TMP" <<'EOF'
# Define the requested items below.
# Save and exit when finished.
EOF


    cat "$TMP"
    # Get editor

    # Open editor with `"$editor" "$TMP"`

    # Parse temp file

    # Set source types to inline and sources in refs
}

_bl_add_trap_editor_return() {

    local -r TMP="$1"

    local old_trap_
    old_trap_=$(trap -p RETURN)
    
    # shellcheck disable=SC2329
    cleanup_return() {
        local status=$?
        rm -rf -- "$TMP"
        trap - RETURN
        [[ -n "${old_trap_:-}" ]] && eval "$old_trap_"
        return "$status"
    }
    trap cleanup_return RETURN
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
# @exitcode 1 Log error.
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