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

    # bl-add
    [ADD_COMMAND]=add
    [ADD_LONG_OPTION_HELP]=--help
    [ADD_LONG_OPTION_CWD]=--cwd
    [ADD_LONG_OPTION_DIR]=--dir
    [ADD_LONG_OPTION_INIT]=--init
    [ADD_LONG_OPTION_FORCE]=--force
    [ADD_OPTION_H]=-h
    [ADD_OPTION_C]=-C
    [ADD_OPTION_D]=-d
    [ADD_OPTION_F]=-f

    # bl (command)
    [BL_LONG_OPTION_HELP]=--help
    [BL_LONG_OPTION_VERSION]=--version
    [BL_OPTION_H]=-h
    [BL_OPTION_V]=-v

    # Config module
    [CONFIG_COMMAND]=config
    [CONFIG_PARSE_REGEX]='^[[:space:]]*([[:alnum:]_-]+)[[:space:]]*=[[:space:]]*(.*)$'
    [CONFIG_SCHEMA_COLOR]=color
    [CONFIG_SCHEMA_DEBUG]=debug
    [CONFIG_SCHEMA_VERBOSE]=verbose
    [CONFIG_TYPE_COLOR]=enum
    [CONFIG_TYPE_DEBUG]=bool
    [CONFIG_TYPE_VERBOSE]=bool
    [CONFIG_ENUM_COLOR]="always auto never"

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

    # bl-help
    [HELP_COMMAND]=help

    # bl-init
    [INIT_COMMAND]=init
    [INIT_LONG_OPTION_HELP]=--help
    [INIT_OPTION_H]=-h

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

    # bl-rm
    [RM_COMMAND]=rm
    
    # bl-version
    [VERSION]=1.1.0
    [VERSION_COMMAND]=version
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

    # Config state (default values)
    [CONFIG_COLOR]=auto
    [CONFIG_DEBUG]=true
    [CONFIG_VERBOSE]=false

    # Log colors
    [LOG_SUPPORTS_COLOR]=true

    # Option values
    [OPTION_COLOR]=""
    [OPTION_DEBUG]=""
    [OPTION_VERBOSE]=""
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
source "$(dirname "${BASH_SOURCE[0]}")/config.bash"
source "$(dirname "${BASH_SOURCE[0]}")/log.bash"
source "$(dirname "${BASH_SOURCE[0]}")/manifest.bash"