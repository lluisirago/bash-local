#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file config.bash
#
# @brief Configuration manager.
# @description Implements functions responsible for managing bl configuration.
#
# Configuration refers to configurable settings.

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public funtions
#
# Functions in this section manage configuration and are intended to be called
# by other modules.

# @description Clears and reloads configuration.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
bl_config_refresh() {
    
    bl_setting_clear "${_BL_CONST[SETTING_LIFETIME_SESSION]}" || return 1
    bl_config_load || return 1
}

# @description Loads bl configuration according to config file.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
bl_config_load() {

    local -a keys values
    
    _bl_config_touch || return 1
    _bl_config_parse keys values || return 1
    _bl_config_set keys values || return 1
}


# MARK: Touch
# -----------------------------------------------------------------------------
# @section Configuration file touch
#
# Functions in this section create configuration file if does not exist.

# @description Touches config file.
#
# Config file is created if does not exist.
#
# Side effects:
# - Touches config file in `_BL_CONST[DIR_CONFIG]`.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged as internal).
# @exitcode 2 External error (logged as internal).
_bl_config_touch() {

    if ! [[ -n "${_BL_CONST[DIR_CONFIG]:-}" ]]; then
        bl_log_internal "missing variable '_BL_CONST[DIR_CONFIG]'"
        return 1
    elif ! [[ -n "${_BL_CONST[PATH_CONFIG]:-}" ]]; then
        bl_log_internal "missing variable '_BL_CONST[PATH_CONFIG]'"
        return 1
    fi

    local -r DIR="${_BL_CONST[DIR_CONFIG]}"
    local -r FILE="${_BL_CONST[PATH_CONFIG]}"

    if [[ ! -f "$FILE" ]]; then
    
        bl_run_external mkdir -p "$DIR" || return 2
        bl_run_external touch "$FILE" || return 2
    fi
}



# MARK: Parse
# -----------------------------------------------------------------------------
# @section Configuration file parser
#
# Functions in this section parse configuration file.

# @description Collects all the settings from the configuration file. Commented,
# empty and invalid lines are ignored. Keys are written in uppercase.
#
# Supported format is INI without sections. Valid file example:
# ```
# key1 = value1
# # Comment
# key2= value2
# key3    =value3
#                       # Empty line
#    key4 = value4
# key5 =                # Also valid, value5 == ""
# ```
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 array Reference to keys array.
# @arg $2 array Reference to values array.
#
# @exitcode 0 Parsing succeeded, but could have found invalid settings.
# @exitcode 1 `_BL_CONST[PATH_CONFIG]` is not defined or is empty (logged in
#             debug).
# @exitcode 2 Config file does not exist (logged).
# @exitcode 3 Config file does not have reading permissions (logged).
_bl_config_parse() {
  
    local -n keys_=$1
    local -n values_=$2

    if ! [[ -n "${_BL_CONST[PATH_CONFIG]:-}" ]]; then

        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_CONFIG]"
        return 1

    elif ! [[ -f "${_BL_CONST[PATH_CONFIG]}" ]]; then

        bl_log "FATAL_NO_FILE" "${_BL_CONST[PATH_CONFIG]}"
        return 2

    elif ! [[ -r "${_BL_CONST[PATH_CONFIG]}" ]]; then

        bl_log "FATAL_NO_PERM" "${_BL_CONST[PATH_CONFIG]}"
        return 3
    fi

    local lineno=0

    while IFS= read -r line; do
      
        ((lineno++))
        
        # Ignore empty lines or comments
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        [[ $line =~ ^[[:space:]]*[#] ]] && continue

        if ! [[ $line =~ ${_BL_CONST[CONFIG_PARSE_REGEX]} ]]; then
            
            bl_log_debug "ERROR_CONFIG_PARSE_INVALID_FORMAT" "$lineno"
            continue
        fi

        keys_+=("${BASH_REMATCH[1]^^}")
        values_+=("${BASH_REMATCH[2]}")
      
    done < "${_BL_CONST[PATH_CONFIG]}"
}


# MARK: Set
# -----------------------------------------------------------------------------
# @section Configuration set
#
# Functions in this section set key-value configurable settings depending on its
# validity.

# @description Sets given key-value configurable settings into state. Ignores
# invalid ones.
#
# @arg $1 array Constant reference to keys array (uppercase).
# @arg $2 array Constant reference to values array.
#
# @exitcode 0 Success.
# @exitcode 1 Arrays have different number of elements (logged in debug).
# @exitcode 2 `_BL_STATE` is not defined (logged in debug).
_bl_config_set() {  

    local -rn KEYS=$1
    local -rn VALUES=$2

    local -ri LENGTH="${#KEYS[@]}"

    if [[ $LENGTH -ne "${#VALUES[@]}" ]]; then
        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi
    [[ $LENGTH -ne 0 ]] || return 0

    if ! declare -p _BL_STATE &>/dev/null; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_STATE"
        return 2
    fi

    local key value error
    local -i i
    for (( i = 0; i < LENGTH; i++ )); do

        key="${KEYS[i]}"
        value="${VALUES[i]}"
        
        bl_setting_set \
            "${_BL_CONST[SETTING_LIFETIME_SESSION]}" "$key" "$value" error
            
        if (( $? == 2 )); then # Ignoring validation error
            bl_log_debug "ERROR_CONFIG_SET_INVALID_SETTING" "$value" "${key,,}"
        fi
    done
}