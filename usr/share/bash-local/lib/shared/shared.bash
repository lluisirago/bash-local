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
# - Configuration
# - Log
# - CLI commands
# - CLI options
declare -grA _BL_CONST=(

    # User-relevant information
    [VERSION]=1.1.0

    # .bl directory
    [BL_DIR]=.bl

    [MANIFEST_FILENAME]=manifest
    [SCOPE_LOCAL]=local
    [SCOPE_SCOPED]=scoped
    [KIND_ALIAS]=alias
    [KIND_FUNCTION]=func
    [KIND_VARIABLE]=var

    [SOURCE_DIR]=source
    [LOCAL_FILENAME]=local
    [SCOPED_FILENAME]=scoped

    # Config file
    [CONFIG_FILE]=${XDG_CONFIG_HOME:-$HOME/.config}/bl/config

    # Config regex
    [CONFIG_REGEX]='^[[:space:]]*([[:alnum:]_-]+)[[:space:]]*=[[:space:]]*(.*)$'

    # Settings name
    [SETTING_VERBOSE]=verbose
    [SETTING_COLOR]=color
    [SETTING_DEBUG]=debug

    # Default config
    [DEFAULT_CONFIG_VERBOSE]=false
    [DEFAULT_CONFIG_COLOR]=auto
    [DEFAULT_CONFIG_DEBUG]=false

    # Log file
    [LOG_DIR]=${XDG_STATE_HOME:-$HOME/.local/state}/bl
    [LOG_FILENAME]=bl.log
    [MAX_LOG_FILE_SIZE]=1048576 # 1MB

    # Log colors
    [COLOR_RED]='\033[0;31m'
    [COLOR_RESET]='\033[0m'

    # CLI commands
    [COMMAND_ADD]=add
    [COMMAND_CONFIG]=config
    [COMMAND_HELP]=help
    [COMMAND_INIT]=init
    [COMMAND_RM]=rm
    [COMMAND_VERSION]=version

    # CLI options
    [OPTION_BL_H]=-h
    [OPTION_BL_V]=-v
    [LONG_OPTION_BL_HELP]=--help
    [LONG_OPTION_BL_VERSION]=--version

    [OPTION_ADD_H]=-h
    [OPTION_ADD_C]=-C
    [OPTION_ADD_D]=-d
    [OPTION_ADD_F]=-f
    [LONG_OPTION_ADD_HELP]=--help
    [LONG_OPTION_ADD_CWD]=--cwd
    [LONG_OPTION_ADD_DIR]=--dir
    [LONG_OPTION_ADD_INIT]=--init
    [LONG_OPTION_ADD_FORCE]=--force

    [OPTION_INIT_H]=-h
    [LONG_OPTION_INIT_HELP]=--help
)

# @description Dynamic state of bash-local.
#
# Defines variables containing information needed between bash-local
# synchronizations and only in the current terminal session.
declare -gA _BL_STATE=(

    [PPD]=""

    # Config state
    [CONFIG_VERBOSE]=""
    [CONFIG_COLOR]=""
    [CONFIG_DEBUG]=""  
)
declare -ga _BL_STATE_PREVIOUS_ENVIRONMENTS=()
declare -ga _BL_STATE_CURRENT_ENVIRONMENTS=()


# MARK: Modules
# -----------------------------------------------------------------------------
# @section Source modules
source "$(dirname "${BASH_SOURCE[0]}")/config.bash"
source "$(dirname "${BASH_SOURCE[0]}")/log.bash"
source "$(dirname "${BASH_SOURCE[0]}")/manifest.bash"


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