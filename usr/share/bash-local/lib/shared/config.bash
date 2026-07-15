#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file config.bash
#
# @brief Configuration manager.
# @description Defines settings and implements functions responsible for
# managing bl configuration.

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
        bl_log_debug "FATAL_UNDEFINED_VARIABLE" "_BL_STATE"
        return 1
    fi

    for key in "${!_BL_STATE[@]}"; do

        [[ $key == CONFIG_* ]] || continue
        _BL_STATE["$key"]=""
    done
}

# @description Decides value of setting according to order of priorities:
# - Option value given by user and stored in `_BL_STATE[OPTION_<KEY>]`
#   (optional).
# - Environment variable defined as `BL_<KEY>=<value>` (optional).
# - Configuration value in `_BL_STATE[CONFIG_<KEY>]` applied in starting
#   procedure.
#
# Side effects:
# - Reads `_BL_STATE`.
#
# @arg $1 string Key (lowercase).
# @arg $2 string Reference to decided value.
#
# @exitcode 0 Success.
# @exitcode 1 Invalid key or value.
bl_config_resolve() {

    local -r KEY="$1"    
    local -n value_=$2
    
    local -r MAYUS_KEY="${KEY^^}"

    if [[ -n "${_BL_STATE[OPTION_$MAYUS_KEY]:-}" ]]; then
        value_="${_BL_STATE[OPTION_$MAYUS_KEY]}"
    else
        local -r KEY_VAR="BL_$MAYUS_KEY"
        value_="${!KEY_VAR:-${_BL_STATE[CONFIG_$MAYUS_KEY]}}"
    fi
    _bl_config_validate "$KEY" "$value_" || return 1
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
# @exitcode 1 Config file does not exist or does not have reading permissions.
_bl_config_parse() {
  
    local -n keys_=$1
    local -n values_=$2

    if ! [[ -n "${_BL_CONST[PATH_CONFIG]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[PATH_CONFIG]"
        return 1
    elif ! [[ -f "${_BL_CONST[PATH_CONFIG]}" ]]; then
        bl_log "FATAL_NO_FILE" "${_BL_CONST[PATH_CONFIG]}"
        return 1
    elif ! [[ -r "${_BL_CONST[PATH_CONFIG]}" ]]; then
        bl_log "FATAL_NO_PERM" "${_BL_CONST[PATH_CONFIG]}"
        return 1
    fi

    local lineno=0
    local retval=0

    while IFS= read -r line; do
      
        ((lineno++))
        
        # Ignore empty lines or comments
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        [[ $line =~ ^[[:space:]]*[#] ]] && continue

        if ! [[ $line =~ ${_BL_CONST[CONFIG_PARSE_REGEX]} ]]; then
            
            bl_log_debug "ERROR_CONFIG_PARSE_BAD_FORMAT" "$lineno"
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

    if [[ "${#keys_[@]}" -ne "${#values_[@]}" ]]; then
        bl_log_debug "FATAL_UNEVEN_ARRAYS"
        return 1
    fi
    [[ "${#keys_[@]}" -ne 0 ]] || return 0

    local -a aux_keys aux_values
    local i
    for (( i = 0; i < ${#keys_[@]}; i++ )); do
        
        if _bl_config_validate "${keys_[i]}" "${values_[i]}"; then
            aux_keys+=("${keys_[i]}")
            aux_values+=("${values_[i]}")
        fi
    done

    keys_=("${aux_keys[@]}")
    values_=("${aux_values[@]}")
}


# MARK: Validate
# -----------------------------------------------------------------------------
# @section Validators
#
# Functions in this section validate key-value settings depending on its type.

# @description Validates a key-value pair according to type and checks extra
# restrictions if exist.
#
# If no specific validator is defined (in case of no extra restrictions),
# key-value pair is only validated by type validator.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Key (lowercase).
# @arg $2 string Value.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Given key is not defined in `_BL_CONFIG_TYPE`.
# @exitcode 2 Validation fails.
_bl_config_validate() {
    
    local -r KEY="$1"
    local -r VALUE="$2"

    local -r MAYUS_KEY="${KEY^^}"

    if ! [[ -v _BL_CONST[CONFIG_TYPE_"$MAYUS_KEY"] ]]; then
        bl_log_debug "ERROR_CONFIG_VALIDATE_BAD_KEY" "$KEY"
        return 1
    fi
    local -r TYPE="${_BL_CONST[CONFIG_TYPE_"$MAYUS_KEY"]}"
    
    if ! "_bl_config_validate_$TYPE" "$KEY" "$VALUE"; then
        bl_log_debug "ERROR_CONFIG_VALIDATE_BAD_VALUE" "$VALUE" "$KEY"
        return 2
    fi
    
    # Extra restrictions
    if declare -F "_bl_config_validate_$KEY" >/dev/null; then
        if ! "_bl_config_validate_$KEY" "$VALUE"; then
            bl_log_debug "ERROR_CONFIG_VALIDATE_BAD_VALUE" "$VALUE" "$KEY"
            return 2
        fi
    fi
}

# @description Validates a bool (true or false).
#
# @arg $1 string Key.
# @arg $2 string Value.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_config_validate_bool() {

    local -r VALUE="$2"
    [[ $VALUE == true || $VALUE == false ]] || return 1
}

# @description Validates an enum according to valid values in `_BL_CONFIG_ENUM`.
#
# @arg $1 string Key (lowercase).
# @arg $2 string Value.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_config_validate_enum() {

    local -r MAYUS_KEY="${1^^}"
    local -r VALUE="$2"
    
    local option
    
    for option in ${_BL_CONST[CONFIG_ENUM_"$MAYUS_KEY"]}; do
        [[ $option == "$VALUE" ]] && return 0
    done
    
    return 1
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
        bl_log_debug "FATAL_UNDEFINED_VARIABLE" "_BL_STATE"
        return 1
    fi

    local i
    for (( i = 0; i < ${#KEYS[@]}; i++)); do
        _BL_STATE[CONFIG_"${KEYS[i]^^}"]="${VALUES[i]}"
    done
}