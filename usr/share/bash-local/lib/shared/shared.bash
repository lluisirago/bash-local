#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file shared.bash
#
# @brief Context definition, logging implementation and assert functions.
# @description Defines constants and dynamic state of bash-local as well as
# functions for logging and asserting.

# Include Guard
[[ -n "${_BL_SHARED_LOADED:-}" ]] && return 0
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
# - Configuration
# - Log
# - CLI commands
# - CLI options
declare -gA _BL_CONST=(

    # bl commands
    [COMMAND_ADD]=add
    [COMMAND_CONFIG]=config
    [COMMAND_HELP]=help
    [COMMAND_INIT]=init
    [COMMAND_RM]=rm
    [COMMAND_VERSION]=version

    # Config module
    [CONFIG_PARSE_REGEX]='^[[:space:]]*([[:alnum:]_-]+)[[:space:]]*=[[:space:]]*(.*)$'
    [CONFIG_SCHEMA_COLOR]=color
    [CONFIG_SCHEMA_DEBUG]=debug
    [CONFIG_SCHEMA_VERBOSE]=verbose

    # Directories
    [DIR_BL]=.bl/
    [DIR_CONFIG]=${XDG_CONFIG_HOME:-$HOME/.config}/bl/
    [DIR_LOG]=${XDG_STATE_HOME:-$HOME/.local/state}/bl/

    # Filenames
    [FILENAME_CONFIG]=config
    [FILENAME_LOG]=bl.log
    [FILENAME_MANIFEST]=manifest
    [FILENAME_SOURCE_LOCAL]=local
    [FILENAME_SOURCE_SCOPED]=scoped

    # Log
    [LOG_COLOR_ERROR]='\033[0;31m' # Red
    [LOG_COLOR_FATAL]='\033[0m'    # None
    [LOG_COLOR_INFO]='\033[0m'     # None
    [LOG_COLOR_RESET]='\033[0m'    # None (to reset)
    [LOG_COLOR_USAGE]='\033[0m'    # None
    [LOG_LEVEL_ERROR]=error
    [LOG_LEVEL_FATAL]=fatal
    [LOG_LEVEL_INFO]=info
    [LOG_LEVEL_USAGE]=usage
    [LOG_INIT_MAX_SIZE]=1048576 # 1MB

    # Manifest
    [MANIFEST_SCHEMA_KIND_ALIAS]=alias
    [MANIFEST_SCHEMA_KIND_FUNCTION]=func
    [MANIFEST_SCHEMA_KIND_VARIABLE]=var
    [MANIFEST_SCHEMA_SCOPE_LOCAL]=local
    [MANIFEST_SCHEMA_SCOPE_SCOPED]=scoped

    # Settings module
    [SETTING_DEFAULT_COLOR]=auto
    [SETTING_DEFAULT_DEBUG]=true
    [SETTING_DEFAULT_DIR]=./
    [SETTING_DEFAULT_FORCE]=false
    [SETTING_DEFAULT_HELP]=false
    [SETTING_DEFAULT_INIT]=false
    [SETTING_DEFAULT_VERBOSE]=false
    [SETTING_DEFAULT_VERSION]=false

    [SETTING_ENUM_COLOR]="always auto never"

    [SETTING_LIFETIME_RUNTIME]=RUNTIME
    [SETTING_LIFETIME_SESSION]=SESSION

    [SETTING_OF_-C]=DIR
    [SETTING_OF_-d]=DIR
    [SETTING_OF_-f]=FORCE
    [SETTING_OF_-h]=HELP
    [SETTING_OF_-v]=VERSION
    [SETTING_OF_--cwd]=DIR
    [SETTING_OF_--dir]=DIR
    [SETTING_OF_--help]=HELP
    [SETTING_OF_--init]=INIT
    [SETTING_OF_--version]=VERSION

    [SETTING_TYPE_COLOR]=enum
    [SETTING_TYPE_DEBUG]=bool
    [SETTING_TYPE_DIR]=dir
    [SETTING_TYPE_FORCE]=bool
    [SETTING_TYPE_HELP]=bool
    [SETTING_TYPE_INIT]=bool
    [SETTING_TYPE_VERBOSE]=bool
    [SETTING_TYPE_VERSION]=bool

    # bl-version
    [VERSION]=1.1.0
)

## Derived Constants

# Directories
_BL_CONST[DIR_SOURCE]="${_BL_CONST[DIR_BL]}source/"

# Paths (dir + filename)
_BL_CONST[PATH_CONFIG]="${_BL_CONST[DIR_CONFIG]}${_BL_CONST[FILENAME_CONFIG]}"
_BL_CONST[PATH_LOG]="${_BL_CONST[DIR_LOG]}${_BL_CONST[FILENAME_LOG]}"
_BL_CONST[PATH_MANIFEST]="${_BL_CONST[DIR_BL]}${_BL_CONST[FILENAME_MANIFEST]}"
_BL_CONST[PATH_SOURCE_LOCAL]="${_BL_CONST[DIR_SOURCE]}${_BL_CONST[FILENAME_SOURCE_LOCAL]}"
_BL_CONST[PATH_SOURCE_SCOPED]="${_BL_CONST[DIR_SOURCE]}${_BL_CONST[FILENAME_SOURCE_SCOPED]}"

readonly -A _BL_CONST


# @description Dynamic state of bash-local.
#
# Defines variables containing information needed between bash-local
# synchronizations and only in the current terminal session.
declare -gA _BL_STATE=(

    [PPD]=""

    # Settings
    [SETTING_RUNTIME_COLOR]=""
    [SETTING_RUNTIME_DIR]=""
    [SETTING_RUNTIME_DEBUG]=""
    [SETTING_RUNTIME_FORCE]=""
    [SETTING_RUNTIME_HELP]=""
    [SETTING_RUNTIME_INIT]=""
    [SETTING_RUNTIME_VERBOSE]=""
    [SETTING_RUNTIME_VERSION]=""

    [SETTING_SESSION_COLOR]=""
    [SETTING_SESSION_DEBUG]=""
    [SETTING_SESSION_VERBOSE]=""

    # Log colors
    [LOG_SUPPORTS_COLOR]=true
)
declare -ga _BL_STATE_PREVIOUS_ENVIRONMENTS=()
declare -ga _BL_STATE_CURRENT_ENVIRONMENTS=()


# MARK: Auxiliar
# -----------------------------------------------------------------------------
# @section Auxiliar functions
bl_run_external() {

    local err retval

    err=$("$@" 2>&1)
    retval=$?

    if (( retval != 0 )); then
        bl_log_debug "FATAL_EXTERNAL" "$err"
        return "$retval"
    fi
}

bl_atomic_write() {

    local -rn LINES=$1
    local -r FILE="$2"

    local -r DIR=${FILE%/*}
    local tmp
    if ! tmp="$(mktemp "$DIR/.tmp.XXXXXX")"; then
        bl_log_debug "FATAL_CREATE_TEMP" "$DIR"
        return 1
    fi
    if ! printf '%s\n' "${LINES[@]}" > "$tmp"; then
        bl_log_debug "FATAL_WRITE" "$tmp"
        rm -f -- "$tmp"
        return 2
    fi  
    bl_run_external mv -f -- "$tmp" "$FILE" || { rm -f -- "$tmp"; return 3; }
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

    [[ -n "$2" ]] || { bl_log "FATAL_NO_DIR" "$1"; return 1; }
    [[ -d "$2" ]] || { bl_log "FATAL_NOT_A_DIR" "$2"; return 1; }
    [[ $2 == $HOME* ]] || { bl_log "FATAL_OUT_HOME" "$2"; return 1; }
}


# MARK: Modules
# -----------------------------------------------------------------------------
# @section Source modules
source "$(dirname "${BASH_SOURCE[0]}")/setting.bash"
source "$(dirname "${BASH_SOURCE[0]}")/config.bash"
source "$(dirname "${BASH_SOURCE[0]}")/log.bash"
source "$(dirname "${BASH_SOURCE[0]}")/manifest.bash"