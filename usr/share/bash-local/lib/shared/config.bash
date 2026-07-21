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

# @description Clears and loads all settings.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error.
bl_config_refresh() {
    
    bl_config_clear || return 1
    bl_config_load || return 1
}

# @description Loads bl configuration according to config file and default
# settings in `_BL_CONST`.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 Internal error.
bl_config_load() {

    local -a keys values

    _bl_config_parse keys values || return 1
    _bl_config_filter keys values || return 1
    _bl_config_apply keys values || return 1
}

# @description Clears configuration values stored in `_BL_STATE`.
#
# Side effects:
# - Writes `_BL_STATE`.
#
# @noargs
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_STATE` is not defined.
bl_config_clear() {

    if ! declare -p _BL_STATE &>/dev/null; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_STATE"
        return 1
    fi

    for key in "${!_BL_STATE[@]}"; do

        [[ $key == CONFIG_* ]] || continue
        _BL_STATE["$key"]=""
    done
}


# MARK: Parse
# -----------------------------------------------------------------------------
# @section Configuration file parser
#
# Functions in this section parse configuration file.

# @description Collects all the settings from the configuration file. Commented,
# empty and invalid lines are ignored.
#
# Supported format is INI without sections. Valid file example:
# ```
# key1 = value1
# # Comment
# key2= value2
# key3    =value3
#                       # Empty line
#    key4 = value4
# key5 =                # Also valid, value5 == "")
# ```
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 array Reference to keys array.
# @arg $2 array Reference to values array.
#
# @exitcode 0 Parsing succeeded, but could have found invalid settings.
# @exitcode 1 `_BL_CONST[PATH_CONFIG]` is not defined or is empty.
# @exitcode 2 Config file does not exist.
# @exitcode 3 Config file does not have reading permissions.
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
    local retval=0

    while IFS= read -r line; do
      
        ((lineno++))
        
        # Ignore empty lines or comments
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        [[ $line =~ ^[[:space:]]*[#] ]] && continue

        if ! [[ $line =~ ${_BL_CONST[CONFIG_PARSE_REGEX]} ]]; then
            
            bl_log_debug "ERROR_CONFIG_PARSE_INVALID_FORMAT" "$lineno"
            continue
        fi

        keys_+=("${BASH_REMATCH[1]}")
        values_+=("${BASH_REMATCH[2]}")
      
    done < "${_BL_CONST[PATH_CONFIG]}"
}


# MARK: Filter
# -----------------------------------------------------------------------------
# @section Settings filter
#
# Functions in this section filter key-value settings depending on its validity.

# @description Filters a set of key-value settings.
#
# If all pairs valid, function is a no-op.
#
# @arg $1 array Reference to keys array.
# @arg $2 array Reference to values array.
#
# @exitcode 0 Success.
# @exitcode 1 Arrays have different number of elements.
_bl_config_filter() {

    local -n keys_=$1
    local -n values_=$2

    local -ri LENGTH="${#keys_[@]}"

    if [[ $LENGTH -ne "${#values_[@]}" ]]; then
        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi
    [[ $LENGTH -ne 0 ]] || return 0

    local key value error retval
    local -a aux_keys aux_values
    local -i i
    for (( i = 0; i < LENGTH; i++ )); do

        key="${keys_[i]}"
        value="${values_[i]}"
        
        bl_setting_validate "${key^^}" "$value" error
        retval=$?

        case $retval in
            0)
                aux_keys+=("$key")
                aux_values+=("$value")
                ;;
            2)
                bl_log_debug "ERROR_CONFIG_FILTER_INVALID_VALUE" "$value" "$key"
                ;;  
        esac
    done

    keys_=("${aux_keys[@]}")
    values_=("${aux_values[@]}")
}


# MARK: Apply
# -----------------------------------------------------------------------------
# @section Settings applier
#
# Functions in this section apply settings into `_BL_STATE`.

# @description Applies given key-value settings into state and defines missing
# ones with default values in `_BL_CONST`.
#
# If there are settings given in arrays or in `_BL_CONST` undefined in
# `_BL_STATE`, function defines them in `_BL_STATE`.
#
# Side effects:
# - Writes `_BL_STATE`.
#
# @arg $1 array Constant reference to keys array.
# @arg $2 array Constant reference to values array.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_STATE` is not defined.
_bl_config_apply() {

    local -rn KEYS=$1
    local -rn VALUES=$2

    if ! declare -p _BL_STATE &>/dev/null; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_STATE"
        return 1
    fi

    local -i i
    for (( i = 0; i < ${#KEYS[@]}; i++)); do
        _BL_STATE[CONFIG_"${KEYS[i]^^}"]="${VALUES[i]}"
    done
}