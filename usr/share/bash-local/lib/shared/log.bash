#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file log.bash
#
# @brief Log file manager and logging functions.
# @description Creates and modifies log files and determines the messages and
# formats for logging.
#
# ---
#
# Log levels:
#
# | Level | Trigger | Color |
# |------|--------|-------|
# | error | Error that does not impede execution | Red |
# | fatal | Error that impedes execution | - |
# | info | State changes | - |
# | usage | Bad CLI usage | - |

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public funtions
#
# Functions in this section manage logs and are intended to be called by other
# modules.

# @description Clears and loads all settings, then configures colors.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged as internal).
bl_log_init() {
    
    _bl_log_touch || return 1
    _bl_log_configure_color || return 1
}

# @description Logs any of the supported messages.
# 
# Each log is determined by a code defined in `_bl_log_translate`.
#
# @arg $1 string Log code.
# @arg $2 string First object to refer to (optional).
# @arg $3 string Second object to refer to (optional).
#
# @exitcode 0 Success.
# @exitcode 1 Emission failed (logged as internal).
bl_log() {

    local -r CODE="$1"
    shift

    local message level
    level="${CODE%%_*}"
    
    _bl_log_translate "$CODE" message "$@" || level="ERROR"
    _bl_log_emit "$level" "$message" || return 1
}

# @description Logs any of the supported debug messages.
# 
# Each log is determined by a code defined in `_bl_log_debug_translate`.
#
# @arg $1 string Log code.
# @arg $2 string First object to refer to (optional).
# @arg $3 string Second object to refer to (optional).
#
# @exitcode 0 Success.
# @exitcode 1 Emission failed (logged as internal).
bl_log_debug() {

    local -r CODE="$1"

    local message level
    level="${CODE%%_*}"
    
    _bl_log_debug_translate "$CODE" message "$2" "$3" || level="ERROR"
    _bl_log_debug_emit "$level" "$message" || return 1
}

# @description Logs an internal error directly to stderr.
# 
# This function does not use the logging system and must not depend on any
# function that may invoke logging.
#
# @arg $1 string Error message.
#
# @exitcode 0 Success.
bl_log_internal() {

    printf 'fatal: %s: %s\n' "${FUNCNAME[1]}" "$1" >&2
}

# MARK: Log file
# -----------------------------------------------------------------------------
# @section Log file manager
#
# Functions in this section manage log file.

# @description Touches log file, rotates it if exceeds max size (1MB) and
# deletes +30 days old files.
#
# Log file is created if does not exist.
#
# Side effects:
# - Reads `_BL_CONST`.
# - Touches, rotates or deletes log files in `_BL_CONST[DIR_LOG]`.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged as internal).
# @exitcode 2 External error (logged as internal).
_bl_log_touch() {

    if ! [[ -n "${_BL_CONST[DIR_LOG]:-}" ]]; then
        bl_log_internal "missing variable '_BL_CONST[DIR_LOG]'"
        return 1
    elif ! [[ -n "${_BL_CONST[PATH_LOG]:-}" ]]; then
        bl_log_internal "missing variable '_BL_CONST[PATH_LOG]'"
        return 1
    fi

    local -r DIR="${_BL_CONST[DIR_LOG]}"
    local -r FILE="${_BL_CONST[PATH_LOG]}"

    if [[ ! -f "$FILE" ]]; then
    
        bl_run_external mkdir -p "$DIR" || return 2
        bl_run_external touch "$FILE" || return 2
    fi

    if [[ -f "$FILE" ]]; then

        local -r SIZE=$(wc -c <"$FILE" 2>/dev/null || echo 0)
        if (( SIZE > _BL_CONST[LOG_FILE_MAX_SIZE])); then

            # Rotate log file
            local -r TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
            local -r OLD_FILE="$DIR/bl-${TIMESTAMP}.log"

            bl_run_external mv "$FILE" "$OLD_FILE" || return 2
            bl_run_external touch "$FILE" || return 2

            # Delete +30 days old files
            bl_run_external find "$DIR" -name "bl-*.log" \
                -type f -mtime +30 -delete || return 2
        fi
    fi
}

# @description Writes entry in log file with the following format:
# [<timestamp>] [<PID>] [<level>] <message>
#
# Using strftime format for timestamp (%Y-%m-%d %H:%M:%S).
#
# Log file is created if does not exist.
#
# Side effects:
# - Writes in log file.
#
# @arg $1 Level of severity.
# @arg $2 Message to write.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[PATH_LOG]` undefined or empty (logged as internal).
# @exitcode 2 Log file does not exist (logged as internal).
# @exitcode 3 Log file does not have writing permissions (logged as internal).
_bl_log_write() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"

    local -r TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    local -r PID=$$

    if ! [[ -n "${_BL_CONST[PATH_LOG]:-}" ]]; then
        bl_log_internal "missing variable '_BL_CONST[PATH_LOG]'"
        return 1
    elif ! [[ -f "${_BL_CONST[PATH_LOG]}" ]]; then
        bl_log_internal "${_BL_CONST[PATH_LOG]}: no such file"
        return 2
    elif ! [[ -w "${_BL_CONST[PATH_LOG]}" ]]; then
        bl_log_internal "permission denied '${_BL_CONST[PATH_LOG]}'"
        return 3
    fi
    
    printf '[%s] [%s] [%s] %s\n' \
        "$TIMESTAMP" "$PID" "$LEVEL" "$MESSAGE" \
        >> "${_BL_CONST[PATH_LOG]}"
}


# MARK: CLI
# -----------------------------------------------------------------------------
# @section CLI logging
#
# Functions in this section log user-facing messages.

# @description Translates log code into message.
#
# If code is unknown, message returned is "unknown log code: <CODE>".
#
# @arg $1 string Code.
# @arg $2 string Reference to message.
# @arg $3... string Objects to refer to (optional).
#
# @exitcode 0 Success.
# @exitcode 1 Unknown code.
_bl_log_translate() {

    local -r CODE="$1"
    local -n message_=$2

    case "$CODE" in

        # Error
        "ERROR_ALREADY_EXISTS")
            message_="$3: already exists in '$4'"
            ;;
        "ERROR_INVALID_ELEMENT")
            message_="$3:$4"
            ;;
        "ERROR_INVALID_FILE_DEFINITION")
            message_="invalid definition in '$3':$4"
            ;;
        "ERROR_INVALID_INLINE_DEFINITION")
            message_="invalid inline definition:$3"
            ;;
        ERROR_INVALID_STDIN_DEFINITION)
            message_="invalid stdin definition:$3"
            ;;
        "ERROR_INVALID_KIND")

            local -a values

            local key
            for key in "${!_BL_CONST[@]}"; do
                [[ $key == "SCHEMA_KIND_"* ]] || continue
                values+=("${_BL_CONST["$key"]}")
            done

            local formatted_values
            _bl_log_format_values values formatted_values

            message_="invalid kind '$3'$formatted_values"
            ;;
        "ERROR_INVALID_NAME")

            message_="invalid name"
            ;;
        "ERROR_INVALID_SCOPE")

            local -a values

            local key
            for key in "${!_BL_CONST[@]}"; do
                [[ $key == "SCHEMA_SCOPE_"* ]] || continue
                values+=("${_BL_CONST["$key"]}")
            done

            local formatted_values
            _bl_log_format_values values formatted_values

            message_="invalid scope '$3'$formatted_values"
            ;;
        "ERROR_NOT_FILE")
            message_="$3: no such file"
            ;;
        "ERROR_NO_STDIN")
            message_="no input received from stdin"
            ;;

        # Fatal
        #   Setting validation
        "FATAL_DEFAULT_EDITOR_NOT_INSTALLED")
            message_="default editor '$3' is not installed; install it or configure a different editor"
            ;;
        "FATAL_DEFAULT_INVALID_BOOL")
            message_="invalid default value '$3' for setting '$4'"
            ;;
        "FATAL_DEFAULT_INVALID_ENUM")
            message_="invalid default value '$3' for setting '$4'"
            ;;
        "FATAL_DEFAULT_NO_DIR")
            message_="missing default directory for setting '$4'"
            ;;
        "FATAL_DEFAULT_OUT_HOME")
            message_="$3: not within '$HOME'"
            ;;
        "FATAL_DEFAULT_NOT_DIR") 
            message_="$3: not a directory"
            ;;
        "FATAL_DEFAULT_NOT_ENV")
            message_="$3: not a bl environment"
            ;;
        "FATAL_EDITOR_NOT_INSTALLED")
            message_="$3: not installed"
            ;;
        "FATAL_INVALID_BOOL")

            local -a values=("true" "false" "no value")

            local formatted_values
            _bl_log_format_values values formatted_values

            message_="invalid boolean value '$3'$formatted_values"
            ;;
        "FATAL_INVALID_ENUM")

            local -a values
            read -r -a values <<< "${_BL_CONST["SETTING_ENUM_$4"]}"

            local formatted_values
            _bl_log_format_values values formatted_values
            message_="invalid value '$3'$formatted_values"
            ;;
        "FATAL_NO_DIR")
            message_="missing directory after '$4'"
            ;;
        "FATAL_OUT_HOME")
            message_="$3: not within '$HOME'"
            ;;
        "FATAL_NOT_DIR") 
            message_="$3: not a directory"
            ;;
        "FATAL_NOT_ENV")
            message_="$3: not a bl environment"
            ;;

        #   Other
        # IS_ENV
        "FATAL_ALREADY_INIT")
            message_="$3: already initialized"
            ;;
        "FATAL_ATOMIC_FAILED")
            message_="validation failed; no elements were added"
            ;;
        "FATAL_DUPLICATE")
            message_="$3: duplicate element name"
            ;;
        "FATAL_INVALID_ENV_VAR")
            
            local -r VAR="BL_$3"
            local VALUE="${!VAR}"
            local -r ERROR="$4"
            
            local error_message
            _bl_log_translate "FATAL_$ERROR" error_message "$VALUE" "$3"
            message_="$VAR: $error_message"
            ;;
        "FATAL_INVALID_OPTION")

            local -r OPTION="$3"
            local -r VALUE="$4"
            local -r ERROR="$5"

            local error_message
            _bl_log_translate "FATAL_$ERROR" error_message "$VALUE" "${_BL_CONST["SETTING_OF_$OPTION"]}"
            message_="$OPTION: $error_message"
            ;;
        "FATAL_MULTIPLE_STDIN")
            message_="cannot read multiple values from stdin; only one argument may use '-'"
            ;;
        "FATAL_NOT_FILE")
            message_="$3: no such file"
            ;;
        "FATAL_NO_PERM")
            message_="$3: permission denied"
            ;;
        "FATAL_NO_VERSION")
            message_="bl version not declared"
            ;;
        
        # Info
        "INFO_INIT")
            message_="Initialized empty environment in '$3'"
            ;;
        "INFO_ADD_SUMMARY_NONE")
            message_="No elements were added"
            ;;
        "INFO_ADD_SUMMARY_SOME")
            message_="Added $3 of $4 elements"
            ;;

        # Usage
        "USAGE_MANY_ARGS")
            message_="too many arguments"
            ;;
        "USAGE_INVALID_ARG_FORMAT")
            message_="invalid argument '$3' (expected: [scope:][kind:]name[=value|=@file|=-])"
            ;;
        "USAGE_INVALID_OPTION")
            message_="unknown option: $3"
            ;;
        "USAGE_INVALID_COMMAND")
            message_="$3: not a bl command"
            ;;

        # Warning
        "WARN_IGNORING_STDIN")
            message_="standard input provided but not used; ignoring it"
            ;;

        # Default
        *)
            message_="unknown log code: $CODE"
            return 2
            ;;
    esac
}

# @description Writes a message to log file and terminal.
#
# @arg $1 string Level (uppercase).
# @arg $2 string Message.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged as internal).
_bl_log_emit() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"

    if ! [[ -v _BL_CONST["LOG_LEVEL_$LEVEL"] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_LEVEL_$LEVEL]'"
        return 1
    fi

    _bl_log_write "${_BL_CONST["LOG_LEVEL_$LEVEL"]}" "$MESSAGE" || return 1
    
    local color_mode color color_reset
    bl_setting_resolve "COLOR" color_mode error
    case $? in
        1) return 1;;
        2) 
            local message
            _bl_log_translate "FATAL_INVALID_ENV_VAR" message "COLOR" "$error"
            bl_log_internal "$message"
            return 2
            ;;
        3)
            local message
            _bl_log_debug_translate "FATAL_DEFAULT_$error" message "$color_mode" "COLOR"
            bl_log_internal "$message"
            return 2
            ;;
        4) return 1;;
    esac
    
    _bl_log_get_color "$color_mode" "$LEVEL" color color_reset || return 1
    _bl_log_print \
        "$color" "$color_reset" \
        "${_BL_CONST["LOG_LEVEL_$LEVEL"]}" "$MESSAGE" || return 1
}

# @description Prints debug message.
#
# Formats:
# - info: <message>
# - usage: <CLI function>: <message>
#          Try '--help' for more information.
# - other levels: <level>: <message>
#
# Side effects:
# - Reads `_BL_CONST`.
# - Writes in terminal.
#
# @arg $1 string Color ANSI escape sequence.
# @arg $2 string Color reset ANSI escape sequence.
# @arg $3 string Level tag (lowercase).
# @arg $4 string Message.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[LOG_LEVEL_INFO]` is not defined (logged as internal).
# @exitcode 2 `_BL_CONST[LOG_LEVEL_USAGE]` is not defined (logged as internal).
_bl_log_print() {

    local -r COLOR="$1"
    local -r COLOR_RESET="$2"
    local -r LEVEL="$3"
    local -r MESSAGE="$4"
    
    if ! [[ -v _BL_CONST[LOG_LEVEL_INFO] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_LEVEL_INFO]'"
        return 1
    elif ! [[ -v _BL_CONST[LOG_LEVEL_USAGE] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_LEVEL_USAGE]'"
        return 2
    fi

    if [[ $LEVEL == "${_BL_CONST[LOG_LEVEL_INFO]}" ]]; then
        
        printf '%b%s%b\n' \
            "$COLOR" "$MESSAGE" "$COLOR_RESET" >&2
            
    elif [[ $LEVEL == "${_BL_CONST[LOG_LEVEL_USAGE]}" ]]; then

        printf "%b%s: %s\nTry '--help' for more information.%b\n" \
            "$COLOR" "${FUNCNAME[-1]}" "$MESSAGE" "$COLOR_RESET" >&2
    else
        printf '%b%s: %s%b\n' \
            "$COLOR" "$LEVEL" "$MESSAGE" "$COLOR_RESET" >&2
    fi
}


# MARK: Debug
# -----------------------------------------------------------------------------
# @section Debug logging
#
# Functions in this section log developer-facing messages.

# @description Translates log code into message.
#
# If code is unknown, message returned is "unknown log code: <CODE>".
#
# @arg $1 string Code.
# @arg $2 string Reference to message.
# @arg $3 string First object to refer to (optional).
# @arg $4 string Second object to refer to (optional).
#
# @exitcode 0 Code is supported.
# @exitcode 1 Unknown code.
_bl_log_debug_translate() {

    local -r CODE="$1"
    local -n message_=$2

    case "$CODE" in

        # Error
        "ERROR_CONFIG_PARSE_INVALID_FORMAT")
            message_="$3: invalid format"
            ;;
        "ERROR_CONFIG_SET_INVALID_SETTING")
            message_="invalid value '$3' for option '$4'"
            ;;

        # Fatal
        "FATAL_ADD_RESOLVE_STDIN_NOT_STDIN")
            message_="given source type is not stdin"
            ;;
        "FATAL_ADD_VALIDATE_SOURCE_UNKNOWN_SOURCE_TYPE")
            message_="$3: unknown source type '$4'"
            ;;
        "FATAL_CREATE_TMP")
            message_="failed to create temporary file in '$3'"
            ;;
        "FATAL_EXTERNAL")
            message_="command $3 failed"
            ;;
        "FATAL_MISSING_VARIABLE")
            message_="required variable '$3' is not defined or is empty"
            ;;
        "FATAL_READ")
            message_="unable to read file '$3'"
            ;;
        "FATAL_SETTING_INVALID_LIFETIME")

            local -a values

            local key
            for key in "${!_BL_CONST[@]}"; do
                [[ $key == "SETTING_LIFETIME_"* ]] || continue
                values+=("${_BL_CONST[$key]}")
            done

            local formatted_values
            _bl_log_format_values values formatted_values

            message_="invalid lifetime '$3'$formatted_values"
            ;;
        "FATAL_UNEVEN_ARRAYS")
            message_="given arrays have different size"
            ;;
        "FATAL_WRITE")
            message_="unable to write file '$3'"
            ;;
        # Default
        *)
            message_="unknown log code: $CODE"
            return 1
            ;;
    esac
}

# @description Writes a debug message to log file and terminal when appropriate.
#
# @arg $1 string Level.
# @arg $2 string Message.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged as internal).
# @exitcode 2 User-related error (logged).
_bl_log_debug_emit() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"

    if ! [[ -v _BL_CONST["LOG_LEVEL_$LEVEL"] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_LEVEL_$LEVEL]'"
        return 1
    fi

    local call_path
    _bl_log_get_call_path call_path
    _bl_log_write "${_BL_CONST["LOG_LEVEL_$LEVEL"]}" "$call_path: $MESSAGE" || return 1
    
    local debug error
    bl_setting_resolve "DEBUG" debug error
    case $? in
        1) return 1;;
        2) 
            local message
            _bl_log_translate "FATAL_INVALID_ENV_VAR" message "DEBUG" "$error"
            bl_log_internal "$message"
            return 2
            ;;
        3)
            local message
            _bl_log_debug_translate "FATAL_DEFAULT_$error" message "$debug" "DEBUG"
            bl_log_internal "$message"
            return 2
            ;;
        4) return 1;;
    esac

    if $debug; then
        
        local color_mode color color_reset
        bl_setting_resolve "COLOR" color_mode error
        case $? in
            1) return 1;;
            2) 
                local message
                _bl_log_translate "FATAL_INVALID_ENV_VAR" message "COLOR" "$error"
                bl_log_internal "$message"
                return 2
                ;;
            3)
                local message
                _bl_log_debug_translate "FATAL_DEFAULT_$error" message "$color_mode" "COLOR"
                bl_log_internal "$message"
                return 2
                ;;
            4) return 1;;
        esac

        _bl_log_get_color "$color_mode" "$LEVEL" color color_reset || return 1
        _bl_log_debug_print \
            "$color" "$color_reset" "$call_path" \
            "${_BL_CONST["LOG_LEVEL_$LEVEL"]}" "$MESSAGE" || return 1
    fi
}

# @description Prints debug message.
#
# Formats:
# - info and usage levels: [DEBUG] <call path>: <message>
# - other levels: [DEBUG] <call path>: <level>: <message>
#
# Side effects:
# - Writes in terminal.
#
# @arg $1 string Color ANSI escape sequence.
# @arg $2 string Color reset ANSI escape sequence.
# @arg $3 string Call path.
# @arg $4 string Level tag (lowercase).
# @arg $5 string Message.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[LOG_LEVEL_INFO]` is not defined (logged as internal).
# @exitcode 2 `_BL_CONST[LOG_LEVEL_USAGE]` is not defined (logged as internal).
_bl_log_debug_print() {

    local -r COLOR="$1"
    local -r COLOR_RESET="$2"
    local -r CALL_PATH="$3"
    local -r LEVEL="$4"
    local -r MESSAGE="$5"
    
    if ! [[ -v _BL_CONST[LOG_LEVEL_INFO] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_LEVEL_INFO]'"
        return 1
    elif ! [[ -v _BL_CONST[LOG_LEVEL_USAGE] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LG_LEVEL_USAGE]'"
        return 2
    fi

    if [[ $LEVEL == "${_BL_CONST[LOG_LEVEL_INFO]}" ||
          $LEVEL == "${_BL_CONST[LOG_LEVEL_USAGE]}" ]]; then
        
        printf '%b[DEBUG] %s: %s%b\n' \
            "$COLOR" "$CALL_PATH" "$MESSAGE" "$COLOR_RESET" >&2
    else
        printf '%b[DEBUG] %s: %s: %s%b\n' \
            "$COLOR" "$CALL_PATH" "$LEVEL" "$MESSAGE" "$COLOR_RESET" >&2
    fi
}


# MARK: Auxiliar
# -----------------------------------------------------------------------------
# @section Auxiliar functions
#
# Functions in this section implement additional functionality for the functions
# above.

# @description Sets `_BL_STATE[SUPPORTS_COLOR]` depending on if terminal
# supports colors or not.
#
# Side effects:
# - Reads `_BL_STATE`.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_STATE[SUPPORTS_COLOR]` is not defined (logged as internal).
_bl_log_configure_color() {

    if ! [[ -v _BL_STATE[LOG_SUPPORTS_COLOR] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_SUPPORTS_COLOR]'"
        return 1
    fi

    if command -v tput >/dev/null &&
        [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then

        _BL_STATE[LOG_SUPPORTS_COLOR]="true"
    else
        _BL_STATE[LOG_SUPPORTS_COLOR]="false"
    fi
}

# @description Gets and formats call path for current log message.
#
# Skips current function and last two callers (logging module), so last function
# shown is the one that invoked the logger.
#
# Call path format example: main->first_caller->second_caller
#
# @arg $1 string Reference to call path
#
# @exitcode 0 Success.
_bl_log_get_call_path() {
    
    local -n call_path_=$1

    call_path_=""
    for ((i = ${#FUNCNAME[@]} - 1; i > 3; i--)); do
        call_path_+="${FUNCNAME[i]}->"
    done
    call_path_+="${FUNCNAME[3]}"
}

# @description Gets both color and color reset according to color mode and log
# level.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Color mode (lowercase).
# @arg $2 string Log level (uppercase).
# @arg $3 string Reference to color ANSI escape sequence.
# @arg $4 string Reference to color reset ANSI escape sequence.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[LOG_COLOR_<LEVEL>]` is not defined (logged as internal).
# @exitcode 2 `_BL_CONST[LOG_COLOR_RESET]` is not defined (logged as internal).
_bl_log_get_color() {

    local -r COLOR_MODE="$1"
    local -r LEVEL="$2"
    local -n out_color=$3
    local -n out_color_reset=$4
    
    out_color=""
    out_color_reset=""

    _bl_log_use_color "$COLOR_MODE" || return 0

    if ! [[ -v _BL_CONST[LOG_COLOR_"$LEVEL"] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_COLOR_$LEVEL]'"
        return 1
    elif ! [[ -v _BL_CONST[LOG_COLOR_RESET] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_COLOR_RESET]'"
        return 2
    fi

    out_color="${_BL_CONST[LOG_COLOR_"$LEVEL"]}"
    out_color_reset="${_BL_CONST[LOG_COLOR_RESET]}"
}

# @description Determines whether color output should be used with four checks:
# - Terminal supports color.
# - `stdout` is connected to terminal.
# - `NO_COLOR` is not defined.
# - Color mode is not 'never'.
#
# If color mode is 'always', returns 0.
#
# Side effects:
# - Reads `_BL_STATE`.
#
# @arg $1 Color mode (lowercase).
#
# @exitcode 0 Should use color.
# @exitcode 1 Should not use it.
_bl_log_use_color() {

    local -r COLOR_MODE="$1"

    [[ $COLOR_MODE == "always" ]] || (
        ${_BL_STATE[LOG_SUPPORTS_COLOR]} &&
        [[ -t 1 ]] &&
        [[ -z ${NO_COLOR-} ]] &&
        [[ $COLOR_MODE != "never" ]]
    )
}

# @description Formats a list of expected values.
#
# @arg $1 array Constant reference to values array.
# @arg $2 string Reference to formatted values.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
_bl_log_format_values() {

    local -rn values_=$1
    local -n expected_values_=$2

    expected_values_=""

    if ! [[ -v _BL_CONST[LOG_VALUES_MAX_SIZE] ]]; then
        bl_log_internal "missing variable '_BL_CONST[LOG_VALUES_MAX_SIZE]'"
        return 1
    fi

    if (( ${#values_[@]} > _BL_CONST[LOG_VALUES_MAX_SIZE] )); then
        expected_values_=" (see --help for valid values)"
    else
        case ${#values_[@]} in
            0)
                ;;
            1)
                expected_values_=${values_[0]}
                ;;
            2)
                expected_values_=" (expected: ${values_[0]} or ${values_[1]})"
                ;;
            *)
                printf -v expected_values_ '%s, ' "${values_[@]:0:${#values_[@]}-1}"
                expected_values_="${expected_values_%, }"
                expected_values_+=" or ${values_[-1]}"
                expected_values_=" (expected: $expected_values_)"
                ;;
        esac
    fi
}