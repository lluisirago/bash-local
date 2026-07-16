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
# @exitcode 1 Internal error.
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
# @exitcode 1 Emission failed.
bl_log() {

    local -r CODE="$1"

    local message level
    level="${CODE%%_*}"
    level="${level,,}"
    
    _bl_log_translate "$CODE" message "$2" "$3" || level="error"
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
# @exitcode 1 Emission failed.
bl_log_debug() {

    local -r CODE="$1"

    local message level
    level="${CODE%%_*}"
    level="${level,,}"
    
    _bl_log_debug_translate "$CODE" message "$2" "$3" || level="error"
    _bl_log_debug_emit "$level" "$message" || return 1
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
# @exitcode 1 Internal error.
_bl_log_touch() {

    local -r FILE="${_BL_CONST[PATH_LOG]}"

    bl_run_external mkdir -p "${_BL_CONST[DIR_LOG]}" || return 1
    bl_run_external touch "$FILE" || return 1

    if [[ -f "$FILE" ]]; then

        local -r SIZE=$(wc -c <"$FILE" 2>/dev/null || echo 0)
        if (( SIZE > _BL_CONST[LOG_INIT_MAX_SIZE])); then

            # Rotate log file
            local -r TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
            local -r OLD_FILE="${_BL_CONST[DIR_LOG]}/bl-${TIMESTAMP}.log"

            bl_run_external mv "$FILE" "$OLD_FILE" || return 1
            bl_run_external touch "$FILE" || return 1

            # Delete +30 days old files
            bl_run_external find "${_BL_CONST[DIR_LOG]}" -name "bl-*.log" \
                -type f -mtime +30 -delete || return 1
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
# @exitcode 1 `_BL_CONST[PATH_LOG]` undefined or empty.
# @exitcode 2 Log file does not have writing permissions.
_bl_log_write() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"

    local -r TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    local -r PID=$$

    if ! [[ -n "${_BL_CONST[PATH_LOG]:-}" ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[PATH_LOG]'"
        return 1
    elif ! [[ -w "${_BL_CONST[PATH_LOG]}" ]]; then
        _bl_log_internal_error "permission denied '${_BL_CONST[PATH_LOG]}'"
        return 2
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
# @arg $3 string First object to refer to (optional).
# @arg $4 string Second object to refer to (optional).
#
# @exitcode 0 Code is supported.
# @exitcode 1 Unknown code.
_bl_log_translate() {

    local -r CODE="$1"
    local -n message_=$2

    case "$CODE" in

        # Error
        "ERROR_IS_DIR")
            message_="$3: is a directory"
            ;;
        "ERROR_NO_FILE")
            message_="$3: no such file"
            ;;

        # Fatal
        "FATAL_ALREADY_INIT") message_="$3: already initialized";;
        "FATAL_NOT_A_DIR") message_="$3: not a directory";;
        "FATAL_UNEVEN_ARRAYS") message_="given arrays have different size";;
        "FATAL_NO_FILE") message_="$3: no such file";;
        "FATAL_NO_DIR") message_="missing directory after '$3'";;
        "FATAL_NO_PERM") message_="$3: permission denied";;
        "FATAL_NO_VERSION") message_="bl version not declared";;
        "FATAL_OUT_HOME") message_="$3: not within '$HOME'";;
        
        # Info
        "INFO_INIT") message_="Initialized empty environment in '$3'";;

        # Usage
        "USAGE_MANY_ARGS") message_="too many arguments";;
        "USAGE_BAD_OPTION") message_="unknown option: $3";;
        "USAGE_BAD_COMMAND") message_="$3: not a bl command";;

        # Default
        *)
            message_="unknown log code: $CODE"
            return 1
            ;;
    esac
}

# @description Writes a message to log file and terminal.
#
# @arg $1 string Level.
# @arg $2 string Message.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error.
_bl_log_emit() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"

    _bl_log_write "$LEVEL" "$MESSAGE"
        
    local color_mode color color_reset
    bl_config_resolve "color" color_mode || return 1
    _bl_log_get_color "$color_mode" "$LEVEL" color color_reset
    _bl_log_print \
        "$color" "$color_reset" "$LEVEL" "$MESSAGE" || return 1
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
# - Writes in terminal.
#
# @arg $1 string Color ANSI escape sequence.
# @arg $2 string Color reset ANSI escape sequence.
# @arg $3 string Level.
# @arg $4 string Message.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[LOG_LEVEL_INFO]` is not defined.
# @exitcode 2 `_BL_CONST[LOG_LEVEL_USAGE]` is not defined.
_bl_log_print() {

    local -r COLOR="$1"
    local -r COLOR_RESET="$2"
    local -r LEVEL="$3"
    local -r MESSAGE="$4"
    
    if ! [[ -v _BL_CONST[LOG_LEVEL_INFO] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LOG_LEVEL_INFO]'"
        return 1
    elif ! [[ -v _BL_CONST[LOG_LEVEL_USAGE] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LOG_LEVEL_USAGE]'"
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
        "ERROR_CONFIG_PARSE_BAD_FORMAT")
            message_="$3: invalid format"
            ;;
        "ERROR_CONFIG_VALIDATE_BAD_KEY")
            message_="key '$3' not found"
            ;;
        "ERROR_CONFIG_VALIDATE_BAD_VALUE")
            message_="invalid value '$3' for '$4'"
            ;;

        # Fatal
        "FATAL_EXTERNAL")
            message_="$3"
            ;;
        "FATAL_MISSING_VARIABLE")
            message_="required variable '$3' is not defined or is empty"
            ;;
        "FATAL_UNEVEN_ARRAYS")
            message_="given arrays have different size"
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
# @exitcode 0 Success.
# @exitcode 1 Internal error.
_bl_log_debug_emit() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"

    local call_path
    _bl_log_get_call_path call_path
    _bl_log_write "$LEVEL" "$call_path: $MESSAGE"
    
    local debug
    bl_config_resolve "debug" debug || return 1
    
    if $debug; then
        
        local color_mode color color_reset
        bl_config_resolve "color" color_mode || return 1
        _bl_log_get_color "$color_mode" "$LEVEL" color color_reset
        _bl_log_debug_print \
            "$color" "$color_reset" "$call_path" "$LEVEL" "$MESSAGE" || return 1
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
# @arg $4 string Level.
# @arg $5 string Message.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[LOG_LEVEL_INFO]` is not defined.
# @exitcode 2 `_BL_CONST[LOG_LEVEL_USAGE]` is not defined.
_bl_log_debug_print() {

    local -r COLOR="$1"
    local -r COLOR_RESET="$2"
    local -r CALL_PATH="$3"
    local -r LEVEL="$4"
    local -r MESSAGE="$5"
    
    if ! [[ -v _BL_CONST[LOG_LEVEL_INFO] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LOG_LEVEL_INFO]'"
        return 1
    elif ! [[ -v _BL_CONST[LOG_LEVEL_USAGE] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LG_LEVEL_USAGE]'"
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
# Functions in this section implement additional functionality for the logging
# functions above.

# @description Sets `_BL_STATE[SUPPORTS_COLOR]` depending on if terminal
# supports colors.
#
# Side effects:
# - Reads `_BL_STATE`.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_STATE[SUPPORTS_COLOR]` is not defined.
_bl_log_configure_color() {

    if ! [[ -v _BL_STATE[LOG_SUPPORTS_COLOR] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LOG_SUPPORTS_COLOR]'"
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
# @arg $2 string Log level (lowercase).
# @arg $3 string Reference to color ANSI escape sequence.
# @arg $4 string Reference to color reset ANSI escape sequence.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST[LOG_COLOR_<LEVEL>]` is not defined.
# @exitcode 2 `_BL_CONST[LOG_COLOR_RESET]` is not defined.
_bl_log_get_color() {

    local -r COLOR_MODE="$1"
    local -r MAYUS_LEVEL="${2^^}"
    local -n out_color=$3
    local -n out_color_reset=$4
    
    out_color=""
    out_color_reset=""

    _bl_log_use_color "$COLOR_MODE" || return 0

    if ! [[ -v _BL_CONST[LOG_COLOR_"$MAYUS_LEVEL"] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LOG_COLOR_$MAYUS_LEVEL]'"
        return 1
    fi

    if ! [[ -v _BL_CONST[LOG_COLOR_RESET] ]]; then
        _bl_log_internal_error "missing variable '_BL_CONST[LOG_COLOR_RESET]'"
        return 2
    fi

    out_color="${_BL_CONST[LOG_COLOR_"$MAYUS_LEVEL"]}"
    out_color_reset="${_BL_CONST[LOG_COLOR_RESET]}"
}

# @description Determines whether color output should be used with four checks:
# - Terminal supports color.
# - `stdout` is connected to terminal.
# - `NO_COLOR` is not defined.
# - Color mode is not "never".
#
# If color mode is "always", returns 0.
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

_bl_log_internal_error() {

    printf 'error: %s: %s\n' "${FUNCNAME[1]}" "$1" >&2
}