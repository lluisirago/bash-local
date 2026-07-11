#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file config.bash
#
# @brief Configuration manager.
# @description Defines settings and implements functions responsible for
# accessing config file. They collect, append and remove rows from/to the file.

# MARK: Settings
# -----------------------------------------------------------------------------
# @section Settings definition
#
# ---
#
# | Setting | Type | Restriction |
# |------|--------|-------|
# | verbose | bool | - |
# | color | enum (auto, always, never) | - |
# | debug | bool | - |
declare -grA _BL_CONFIG_TYPE=(

	[${_BL_CONST[SETTING_VERBOSE]}]=bool
    [${_BL_CONST[SETTING_COLOR]}]=enum
    [${_BL_CONST[SETTING_DEBUG]}]=bool
)

declare -grA _BL_CONFIG_ENUM=(

    [${_BL_CONST[SETTING_COLOR]}]="auto always never"
)


# MARK: Start
# -----------------------------------------------------------------------------
# @section Start configuration
#
# Functions in this section manage configuration start procedure.

_bl_start_config() {

    local -a keys values
    _bl_config_parse keys values
    _bl_config_filter keys values

    echo "${keys[@]}"
    echo "${values[@]}"
    # _bl_config_load keys values
}

# MARK: Parse
# -----------------------------------------------------------------------------
# @section Configuration file parser
#
# Functions in this section parse configuration file.

# @description Collects all the settings from the configuration file.
#
# Supported format is INI without sections. Valid formats:
# ```
# key1 = value1
# # Comment
# key2= value2
# key3    =value3
#                       # Blank line
#    key4 = value4
# key5 =                # Also valid, value5 == "")
# ```
#
# Side effects:
# - Logs FATAL_NO_CONFIG if config file does not exist.
# - Logs FATAL_NO_PERM_CONFIG if cannot read config file.
# - Logs ERROR_BAD_SETTING if setting format is invalid.
#
# @arg $1 array  Reference to keys array.
# @arg $2 array  Reference to values array.
#
# @exitcode 0 Parsing succeeded.
# @exitcode 1 Config file does not exist or does not have reading permissions.
# @exitcode 2 Parsing ended with some invalid settings.
_bl_config_parse() {
  
    local -n keys_=$1
    local -n values_=$2

    [[ -f "${_BL_CONST[CONFIG_FILE]}" ]] || { _bl_log "FATAL_NO_CONFIG_FILE"; return 1; }
    [[ -r "${_BL_CONST[CONFIG_FILE]}" ]] || { _bl_log "FATAL_NO_PERM_CONFIG_FILE"; return 1; }

    local lineno=0
    local retval=0

    while IFS= read -r line; do
      
        ((lineno++))
        
        # Ignore empty lines or comments
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        [[ $line =~ ^[[:space:]]*[#] ]] && continue

        if ! [[ $line =~ ${_BL_CONST[CONFIG_REGEX]} ]]; then
            _bl_log_debug "ERROR_CONFIG_FILE_BAD_FORMAT" "$lineno"
            retval=2
            continue
        fi

        keys_+=("${BASH_REMATCH[1]}")
        values_+=("${BASH_REMATCH[2]}")
      
    done < "${_BL_CONST[CONFIG_FILE]}"

    return $retval
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
# @exitcode 0 Filtering succeeds.
# @exitcode 1 Arrays have different number of elements.
_bl_config_filter() {

    local -rn keys_=$1
    local -rn values_=$2

    if [[ "${#keys_[@]}" -ne "${#values_[@]}" ]]; then
        _bl_log_debug "FATAL_UNEVEN_ARRAYS" "${FUNCNAME[0]}"
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
# - Logs ERROR_BAD_KEY if key does not exist.
# - Logs ERROR_BAD_VALUE if invalid value.
#
# @arg $1 string Key.
# @arg $2 string Value.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Given key is not defined in `_BL_CONFIG_TYPE`.
# @exitcode 2 Validation fails.
_bl_config_validate() {

    local -r KEY="$1"
    local -r VALUE="$2"

    if ! [[ -v _BL_CONFIG_TYPE[$KEY] ]]; then
        _bl_log_debug "ERROR_CONFIG_FILE_BAD_KEY" "$KEY"
        return 1
    fi
    local -r TYPE=${_BL_CONFIG_TYPE[$KEY]}

    if ! "_bl_config_validate_$TYPE" "$KEY" "$VALUE"; then
        _bl_log_debug "ERROR_CONFIG_FILE_BAD_VALUE" "$VALUE" "$KEY"
        return 2
    fi

    # Extra restrictions
    if declare -F "_bl_config_validate_$KEY" >/dev/null; then
        if ! "_bl_config_validate_$KEY" "$VALUE"; then
            _bl_log_debug "ERROR_CONFIG_FILE_BAD_VALUE" "$VALUE" "$KEY"
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
#
# @see Used in [_bl_config_validate](#_bl_config_validate)
_bl_config_validate_bool() {

    local -r VALUE="$2"
    [[ $VALUE == true || $VALUE == false ]] || return 1
}

# @description Validates an enum according to valid values in `_BL_CONFIG_ENUM`.
#
# @arg $1 string Key.
# @arg $2 string Value.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
#
# @see Used in [_bl_config_validate](#_bl_config_validate)
_bl_config_validate_enum() {

    local -r KEY="$1"
    local -r VALUE="$2"

    local option

    for option in ${_BL_CONFIG_ENUM[$KEY]}; do
        [[ $VALUE == "$option" ]] && return 0
    done
    
    return 1
}

_bl_config_collect() {
    true
}

_bl_config_add() {
    true
}

_bl_config_remove() {
    true
}