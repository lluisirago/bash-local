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
# Log types:
#
# | Type | Trigger | Color |
# |------|--------|-------|
# | debug | Internal error written in log file (in terminal when debug is
# enabled) | Yellow |
# | error | Error that does not impede execution | Red |
# | fatal | Error that impedes execution | - |
# | info | State changes | - |
# | usage | Bad CLI usage | - |

_bl_log_init() {

    local -r LOG_FILE="${_BL_CONST[LOG_DIR]}/${_BL_CONST[LOG_FILENAME]}"

    mkdir -p "${_BL_CONST[LOG_DIR]}" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null

    if [[ -f "$LOG_FILE" ]]; then

        local -r SIZE=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
        if (( SIZE > _BL_CONST[MAX_LOG_FILE_SIZE])); then

            # Rotate log file
            local -r TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
            local -r OLD_LOG_FILE="${_BL_CONST[LOG_DIR]}/bl-${TIMESTAMP}.log"

            mv "$LOG_FILE" "$OLD_LOG_FILE" 2>/dev/null
            touch "$LOG_FILE" 2>/dev/null

            # Delete +30 days old files
            find "${_BL_CONST[LOG_DIR]}" -name "bl-*.log" -type f \
                 -mtime +30 -delete 2>/dev/null
        fi
    fi
}
_bl_log_init

_bl_log_write() {

    local -r LEVEL="$1"
    local -r MESSAGE="$2"
    local -r TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    local -r PID=$$

    local -r LOG_FILE="${_BL_CONST[LOG_DIR]}/${_BL_CONST[LOG_FILENAME]}"

    if [[ -n "${LOG_FILE:-}" && -w "$LOG_FILE" ]]; then
        echo "[$TIMESTAMP] [$PID] [$LEVEL] $MESSAGE" >> "$LOG_FILE"
    fi
}

_bl_log_debug() {

    _bl_log_write "debug" "$1"
    # Añadir lógica para variable DEBUG activada
    
}

# @description Logs an error, writing the given message in log file and
# printing it to stderr. If terminal supports color, the message will be red.
#
# Side effects:
# - Writes in log file
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_error() {

    _bl_log_write "error" "$1"
    echo -e "${_BL_CONST[COLOR_RED]}error: $1${_BL_CONST[COLOR_RESET]}" >&2
}

# @description Logs a fatal error, writing the given message in log file and
# printing it to stderr.
#
# Side effects:
# - Writes in log file
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_fatal() {
    
    _bl_log_write "fatal" "$1"
    echo -e "fatal: $1" >&2
}

# @description Logs information for state changes, writing the given message in
# log file and printing it to stderr.
#
# Side effects:
# - Writes in log file
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_info() {

    _bl_log_write "info" "$1"
    echo -e "$1" >&2
}

# @description Logs information for correct CLI usage, writing the given message
# in log file and printing it to stderr.
#
# Side effects:
# - Writes in log file
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_usage() {

    _bl_log_write "usage" "$1"
    echo -e "bl: $1" >&2
    echo -e "Try '--help' for more information." >&2
}

# @description Logs any of the supported messages.
# 
# Each log is determined by a code.
#
# @arg $1 string Log code
# @arg $2 string Object to refer to
#
# @see Used in [cli.bash](./cli.md)
_bl_log() {

    local code="$1"

    case "$code" in

        # Error
        "ERROR_NO_FILE")    _bl_log_error "$2: no such file";;
        "ERROR_IS_DIR")     _bl_log_error "$2: is a directory";;

        # Fatal
        "FATAL_NO_DIR")         _bl_log_fatal "missing directory after '$2'";;
        "FATAL_NOT_A_DIR")      _bl_log_fatal "$2: not a directory";;
        "FATAL_OUT_HOME")       _bl_log_fatal "$2: not within '$HOME'";;
        "FATAL_NO_VERSION")     _bl_log_fatal "bl version not declared";;
        "FATAL_ALREADY_INIT")   _bl_log_fatal "$2: already initialized";;

        # Info
        "INFO_INIT") _bl_log_info "Initialized empty environment in '$2'";;

        # Usage
        "USAGE_MANY_ARGS")   _bl_log_usage "too many arguments";;
        "USAGE_BAD_OPTION")  _bl_log_usage "unknown option: $2";;
        "USAGE_BAD_COMMAND") _bl_log_usage "$2: not a bl command";;

        # Others
        "USAGE")
            echo "usage: bl [-v | --version] [-h | --help] <command> [<args>]"
            ;;
        "COMMANDS_LIST")
            {
                echo "  init:Initialize a new environment";
                echo "  add:Add aliases, functions and/or variables to an environment";
                echo "  rm:Remove elements from an environment"
            } | column -t -s ':'
            ;;
        "HELP")
            _bl_log "USAGE"
            echo ""
            echo "These are common bl commands:"
            echo ""
            _bl_log "COMMANDS_LIST"
            ;;

        # Default
        *) _bl_log_error "unknown error: $*";;
    esac
}