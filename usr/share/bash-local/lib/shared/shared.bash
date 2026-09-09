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

    [ADD_ARGUMENT_REGEX]='^([^:=]+:){0,2}[^:=]+(=(-|@.+|[^@].*|))?$'
    [ADD_EDITOR_TEMPLATE_HEADER]="# Define the requested elements below."$'\n'"# Save and exit when finished."
    [ADD_EDITOR_TEMPLATE_PROMPT_BEGIN]=">>>"
    [ADD_EDITOR_TEMPLATE_PROMPT_END]="<<<"
    [ADD_SHELL_ID_REGEX]='^[a-zA-Z_][a-zA-Z0-9_]*$'
    [ADD_SOURCE_TYPE_EDITOR]=EDITOR
    [ADD_SOURCE_TYPE_FILE]=FILE
    [ADD_SOURCE_TYPE_INLINE]=INLINE
    [ADD_SOURCE_TYPE_STDIN]=STDIN

    # Editor argument
    [ARG_OF_code]=--wait
    [ARG_OF_code-insiders]=--wait
    [ARG_OF_codium]=--wait
    [ARG_OF_subl]=--wait
    
    # bl commands
    [COMMAND_ADD]=add
    [COMMAND_CONFIG]=config
    [COMMAND_HELP]=help
    [COMMAND_INIT]=init
    [COMMAND_RM]=rm
    [COMMAND_VERSION]=version

    # Config module
    [CONFIG_PARSE_REGEX]='^[[:space:]]*([[:alnum:]_-]+)[[:space:]]*=[[:space:]]*(.*)$'

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
    [LOG_COLOR_WARN]='\033[33m'    # Yellow
    [LOG_FILE_MAX_SIZE]=1048576 # 1MB
    [LOG_LEVEL_ERROR]=error
    [LOG_LEVEL_FATAL]=fatal
    [LOG_LEVEL_INFO]=info
    [LOG_LEVEL_USAGE]=usage
    [LOG_LEVEL_WARN]=warning
    [LOG_VALUES_MAX_SIZE]=5

    # Schema
    [SCHEMA_KIND_ALIAS]=alias
    [SCHEMA_KIND_FUNCTION]=func
    [SCHEMA_KIND_VARIABLE]=var
    [SCHEMA_SCOPE_LOCAL]=local
    [SCHEMA_SCOPE_SCOPED]=scoped

    # Settings module
    [SETTING_DEFAULT_ATOMIC]=false
    [SETTING_DEFAULT_COLOR]=auto
    [SETTING_DEFAULT_DEBUG]=true # Change before deployment
    [SETTING_DEFAULT_EDITOR]=vi
    [SETTING_DEFAULT_ENV]=./
    [SETTING_DEFAULT_FORCE]=false
    [SETTING_DEFAULT_HELP]=false
    [SETTING_DEFAULT_INIT]=false
    [SETTING_DEFAULT_VERSION]=false

    [SETTING_ENUM_EDITOR]="code code-insiders codium emacs helix hx kak kakoune micro nano nvim subl vi vim" # Update 'add.bash: _bl_add_get_editor_arg' if changed
    [SETTING_ENUM_COLOR]="always auto never"

    [SETTING_LIFETIME_RUNTIME]=RUNTIME
    [SETTING_LIFETIME_SESSION]=SESSION

    [SETTING_OF_-C]=ENV
    [SETTING_OF_-d]=ENV
    [SETTING_OF_-f]=FORCE
    [SETTING_OF_-h]=HELP
    [SETTING_OF_-V]=VERSION
    [SETTING_OF_--atomic]=ATOMIC
    [SETTING_OF_--color]=COLOR
    [SETTING_OF_--cwd]=ENV
    [SETTING_OF_--dir]=ENV
    [SETTING_OF_--editor]=EDITOR
    [SETTING_OF_--force]=FORCE
    [SETTING_OF_--help]=HELP
    [SETTING_OF_--init]=INIT
    [SETTING_OF_--version]=VERSION

    [SETTING_TYPE_ATOMIC]=bool
    [SETTING_TYPE_COLOR]=enum
    [SETTING_TYPE_DEBUG]=bool
    [SETTING_TYPE_EDITOR]=enum
    [SETTING_TYPE_ENV]=dir
    [SETTING_TYPE_FORCE]=bool
    [SETTING_TYPE_HELP]=bool
    [SETTING_TYPE_INIT]=bool
    [SETTING_TYPE_VERSION]=bool

    # bl-version
    [VERSION]=1.1.0
)

## Derived Constants

_BL_CONST[ADD_DEFAULT_KIND]="${_BL_CONST[SCHEMA_KIND_VARIABLE]}"
_BL_CONST[ADD_DEFAULT_SCOPE]="${_BL_CONST[SCHEMA_SCOPE_LOCAL]}"


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
    [SETTING_RUNTIME_ATOMIC]=""
    [SETTING_RUNTIME_COLOR]=""
    [SETTING_RUNTIME_DEBUG]=""
    [SETTING_RUNTIME_EDITOR]=""
    [SETTING_RUNTIME_ENV]=""
    [SETTING_RUNTIME_FORCE]=""
    [SETTING_RUNTIME_HELP]=""
    [SETTING_RUNTIME_INIT]=""
    [SETTING_RUNTIME_VERSION]=""

    [SETTING_SESSION_ATOMIC]=""
    [SETTING_SESSION_COLOR]=""
    [SETTING_SESSION_DEBUG]=""
    [SETTING_SESSION_EDITOR]=""

    # Log colors
    [LOG_SUPPORTS_COLOR]=true
)
declare -ga _BL_STATE_PREVIOUS_ENVIRONMENTS=()
declare -ga _BL_STATE_CURRENT_ENVIRONMENTS=()


# MARK: Auxiliar
# -----------------------------------------------------------------------------
# @section Auxiliar functions
bl_run_external() {

    local err status

    err=$("$@" 2>&1)
    status=$?

    if (( status != 0 )); then
        bl_log_internal "$err"
        return "$status"
    fi
}


# MARK: Modules
# -----------------------------------------------------------------------------
# @section Source modules
source "$(dirname "${BASH_SOURCE[0]}")/setting.bash"
source "$(dirname "${BASH_SOURCE[0]}")/log.bash"