#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file shared.bash
#
# @brief Context definition, logging implementation and assert functions.
# @description Defines constants and dynamic state of bash-local as well as
# functions for logging and asserting.

# Include Guard
if [[ -n "${_BL_SHARED_LOADED:-}" ]]; then
    return 0
fi
declare -gr _BL_SHARED_LOADED=1


# MARK: Context
# -----------------------------------------------------------------------------
# @section Context definition
#
# Defines constants and dynamic state of bash-local.

# @description Constants for bash-local.
#
# The constants refer to:
# - User-relevant information
# - `.bl` directory
# - Log colors
# - CLI commands
# - CLI options
declare -grA _BL_CONST=(

    # User-relevant information
    [VERSION]="1.1.0"

    # .bl directory
    [BL_DIR]=".bl"

    [MANIFEST_FILE]="manifest"
    [SCOPE_LOCAL]="local"
    [SCOPE_SCOPED]="scoped"
    [KIND_ALIAS]="alias"
    [KIND_FUNCTION]="func"
    [KIND_VARIABLE]="var"

    [SOURCE_DIR]="source"
    [LOCAL_FILE]="local"
    [SCOPED_FILE]="scoped"

    # Log file
    [LOG_FILE]="bl.log"
    [MAX_LOG_FILE_SIZE]="1048576" # 1MB

    # Log colors
    [COLOR_RED]='\033[0;31m'
    [COLOR_RESET]='\033[0m'

    # CLI commands
    [COMMAND_ADD]="add"
    [COMMAND_CONFIG]="config"
    [COMMAND_HELP]="help"
    [COMMAND_INIT]="init"
    [COMMAND_RM]="rm"
    [COMMAND_VERSION]="version"

    # CLI options
    [OPTION_BL_H]="-h"
    [OPTION_BL_V]="-v"
    [LONG_OPTION_BL_HELP]="--help"
    [LONG_OPTION_BL_VERSION]="--version"

    [OPTION_ADD_H]="-h"
    [OPTION_ADD_C]="-C"
    [OPTION_ADD_D]="-d"
    [OPTION_ADD_F]="-f"
    [LONG_OPTION_ADD_HELP]="--help"
    [LONG_OPTION_ADD_CWD]="--cwd"
    [LONG_OPTION_ADD_DIR]="--dir"
    [LONG_OPTION_ADD_INIT]="--init"
    [LONG_OPTION_ADD_FORCE]="--force"

    [OPTION_INIT_H]="-h"
    [LONG_OPTION_INIT_HELP]="--help"
)

# @description Dynamic state of bash-local.
#
# Defines the variables containing information needed between bash-local
# synchronizations and only in the current terminal session.
declare -gA _BL_STATE=(
    [PPD]=""
)
declare -ga _BL_STATE_PREVIOUS_ENVIRONMENTS=()
declare -ga _BL_STATE_CURRENT_ENVIRONMENTS=()

declare -g _BL_CONF=(
    [LOG_DIR]="$HOME/.local/state/bl"
)


# MARK: Log
# -----------------------------------------------------------------------------
# @section Logging functions
#
# Functions in this section determine the messages and formats for logging.
#
# ---
#
# Log levels:
#
# | Type | Trigger | Color |
# |------|--------|-------|
# | debug | Internal error written in log file (in terminal when debug is
# enabled) | - |
# | error | Error that does not impede execution | - |
# | fatal | Error that impedes execution | Red |
# | info | State changes | - |
# | usage | Bas CLI usage | - |

_bl_log_init() {

    local -r LOG_FILE="${_BL_CONF[LOG_DIR]}/${_BL_CONST[LOG_FILE]}"

    mkdir -p "${_BL_CONF[LOG_DIR]}" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null

    if [[ -f "$LOG_FILE" ]]; then

        local -r SIZE=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
        if (( SIZE > _BL_CONST[MAX_LOG_FILE_SIZE])); then

            # Rotate log file
            local -r TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
            local -r OLD_LOG_FILE="${_BL_CONF[LOG_DIR]}/bl-${TIMESTAMP}.log"

            mv "$LOG_FILE" "$OLD_LOG_FILE" 2>/dev/null
            touch "$LOG_FILE" 2>/dev/null

            # Delete +30 days old files
            find "${_BL_CONF[LOG_DIR]}" -name "bl-*.log" -type f \
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

    local -r LOG_FILE="${_BL_CONF[LOG_DIR]}/${_BL_CONST[LOG_FILE]}"

    if [[ -n "${LOG_FILE:-}" && -w "$LOG_FILE" ]]; then
        echo "[$TIMESTAMP] [$PID] [$LEVEL] $MESSAGE" >> "$LOG_FILE"
    fi
}

_bl_log_debug() {


    [[ "$BL_DEBUG" == true ]] && _bl_log_write "debug" "$1"
    
    }

# @description Logs an error, printing the given message to stderr.
#
# If terminal supports color, the message will be yellow.
#
# Side effects:
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_error() {

    echo -e "${_BL_CONST[COLOR_RED]}error: $1${_BL_CONST[COLOR_RESET]}" >&2
}

# @description Logs a fatal error, printing the given message to stderr.
#
# Side effects:
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_fatal() { echo -e "fatal: $1" >&2; }

# @description Logs information for state changes, printing the given message to
# stderr.
#
# Side effects:
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_info() { echo -e "$1" >&2; }

# @description Logs information for correct CLI usage, printing the given
# message to stderr.
#
# Side effects:
# - Writes to stderr
#
# @see Used in [_bl_log](#_bl_log)
_bl_log_usage() {

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
    shift

    case "$code" in

        # Error
        "ERROR_NO_FILE")    _bl_log_error "$1: no such file";;
        "ERROR_IS_DIR")     _bl_log_error "$1: is a directory";;

        # Fatal
        "FATAL_NO_DIR")         _bl_log_fatal "missing directory after '$1'";;
        "FATAL_NOT_A_DIR")      _bl_log_fatal "$1: not a directory";;
        "FATAL_OUT_HOME")       _bl_log_fatal "$1: not within '$HOME'";;
        "FATAL_NO_VERSION")     _bl_log_fatal "bl version not declared";;
        "FATAL_ALREADY_INIT")   _bl_log_fatal "$1: already initialized";;

        # Info
        "INFO_INIT") _bl_log_info "Initialized empty environment in '$1'";;

        # Usage
        "USAGE_MANY_ARGS")   _bl_log_usage "too many arguments";;
        "USAGE_BAD_OPTION")  _bl_log_usage "unknown option: $1";;
        "USAGE_BAD_COMMAND") _bl_log_usage "$1: not a bl command";;

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


# MARK: Assert
# -----------------------------------------------------------------------------
# @section Asserting functions
#
# Functions in this section implement checks used in CLI, logging the error if
# required.

# @description Checks if a directory is valid.
#
# Logs the error in case directory is invalid.
#
# @arg $1 string Command that called the function
# @arg $2 string Path to directory
#
# @see Used in [cli.bash](./cli.md)
_bl_assert_valid_dir() {    

    [[ -n "$2" ]] || { _bl_log "FATAL_NO_DIR" "$1"; return 1; }
    [[ -d "$2" ]] || { _bl_log "FATAL_NOT_A_DIR" "$2"; return 1; }
    [[ $2 == $HOME* ]] || { _bl_log "FATAL_OUT_HOME" "$2"; return 1; }
}