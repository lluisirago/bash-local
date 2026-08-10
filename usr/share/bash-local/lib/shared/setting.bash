#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file setting.bash
#
# @brief Setting manager.
# @description Implements functions responsible for managing bl settings.

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public funtions
#
# Functions in this section manage configuration and are intended to be called
# by other modules.

# @description Decides value of setting according to order of priorities:
# 1. Runtime setting `_BL_STATE[SETTING_RUNTIME_<KEY>]`.
# 2. Environment variable `BL_<KEY>`.
# 3. Session setting `_BL_STATE[SETTING_SESSION_<KEY>]`.
# 4. Default value in `_BL_CONST[SETTING_DEFAULT_<KEY>]`.
#
# If unknown setting, decided value is empty.
#
# Side effects:
# - Reads `_BL_STATE`.
# - Reads `_BL_CONST`.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Reference to decided value.
# @arg $3 string Reference to environment variable validation error code.
#
# @exitcode 0 Success.
# @exitcode 1 Internal validation error (logged in debug).
# @exitcode 2 Resolved using fallback after ignoring an invalid environment
#             variable.
# @exitcode 3 Invalid default value, and the environment variable is either
#             valid or not set.
# @exitcode 4 Unknown setting (logged in debug).
bl_setting_resolve() {

    local -r KEY="$1"    
    local -n value_=$2
    local -n error_=$3

    value_=""

    # 1. CLI option
    if [[ -n "${_BL_STATE["SETTING_RUNTIME_$KEY"]:-}" ]]; then
        
        value_="${_BL_STATE["SETTING_RUNTIME_$KEY"]}"
        return 0
    fi

    # 2. Environment variable
    local -r KEY_ENV_VAR="BL_$KEY"

    local invalid_env_var=false
    local aux_error
    
    if [[ -v $KEY_ENV_VAR ]]; then

        bl_setting_validate "$KEY" "${!KEY_ENV_VAR}" aux_error
        case $? in
            0)  value_="${!KEY_ENV_VAR}"; return 0;;
            1)  return 1;;
            2)  value_="${!KEY_ENV_VAR}"; invalid_env_var=true; error_="$aux_error";;
        esac
    fi
    
    # 3. Configuration
    if [[ -n "${_BL_STATE["SETTING_SESSION_$KEY"]:-}" ]]; then

        value_="${_BL_STATE["SETTING_SESSION_$KEY"]}"
        [[ $invalid_env_var == true ]] && return 2 || return 0
    fi
    
    # 4. Default value
    if [[ -v _BL_CONST["SETTING_DEFAULT_$KEY"] ]]; then

        bl_setting_validate "$KEY" "${_BL_CONST["SETTING_DEFAULT_$KEY"]}" aux_error
        case $? in
            0)  
                value_="${_BL_CONST["SETTING_DEFAULT_$KEY"]}"
                [[ $invalid_env_var == true ]] && return 2 || return 0
                ;;
            1)  
                return 1
                ;;
            2)  
                if [[ $invalid_env_var == true ]]; then
                    return 2
                else
                    value_="${_BL_CONST["SETTING_DEFAULT_$KEY"]}"
                    error_=$aux_error
                    return 3
                fi
                ;;
        esac
    fi

    bl_log_debug "FATAL_SETTING_RESOLVE_INVALID_SETTING" "${KEY,,}" # (lowercase)
    return 4
}

# @description Sets a value to a setting given its lifetime and key.
#
# Supported lifetimes are defined in `_BL_CONST[SETTING_LIFETIME_*]`.
#
# Side effects:
# - Reads `_BL_CONST`.
# - Writes `_BL_STATE`.
#
# @arg $1 string Setting lifetime (uppercase).
# @arg $2 string Key (uppercase).
# @arg $3 string Value.
# @arg $4 string Reference to validation error code.
#
# @exitcode 0 Success.
# @exitcode 1 Given key type is not defined in `_BL_CONST` (logged in debug).
# @exitcode 2 Validation fails.
# @exitcode 3 Invalid lifetime (logged in debug).
# @exitcode 4 Given setting is not defined in `_BL_STATE` (logged in debug).
bl_setting_set() {

    local -r SETTING_LIFETIME="$1"
    local -r KEY="$2"
    local -r VALUE="$3"
    local -n error_=$4

    error_=""
    
    bl_setting_validate "$KEY" "$VALUE" error_ || return
    
    local state_key
    case $SETTING_LIFETIME in

        "${_BL_CONST[SETTING_LIFETIME_RUNTIME]}")
            state_key="SETTING_${_BL_CONST[SETTING_LIFETIME_RUNTIME]}_${KEY}"
            ;;

        "${_BL_CONST[SETTING_LIFETIME_SESSION]}")
            state_key="SETTING_${_BL_CONST[SETTING_LIFETIME_SESSION]}_${KEY}"
            ;;

        *)
            bl_log_debug \
                "FATAL_SETTING_INVALID_LIFETIME" "$SETTING_LIFETIME"
            return 3
    esac

    if ! [[ -v _BL_STATE["$state_key"] ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_STATE[$state_key]"
        return 4
    fi

    _BL_STATE["$state_key"]="$VALUE"
}

# @description Validates a key-value pair according to type and checks extra
# restrictions if exist.
#
# If no specific validator is defined (in case of no extra restrictions),
# key-value pair is only validated by type validator.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Value.
# @arg $3 string Reference to error code.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Given key type is not defined in `_BL_CONST` (logged in debug).
# @exitcode 2 Validation fails.
bl_setting_validate() {

    local -r KEY="$1"
    local -r VALUE="$2"
    local -n error__=$3

    error__=""

    local -r MINUS_KEY="${KEY,,}"
    
    # Key
    if ! [[ -v _BL_CONST["SETTING_TYPE_$KEY"] ]]; then
        bl_log_debug "ERROR_SETTING_VALIDATE_INVALID_KEY" "$MINUS_KEY"
        return 1
    fi
    
    # Value
    local -r TYPE="${_BL_CONST[SETTING_TYPE_"$KEY"]}"
    "_bl_setting_validate_$TYPE" "$KEY" "$VALUE" error__ || return 2
    
    # Extra restrictions
    if declare -F "_bl_setting_validate_${MINUS_KEY}" >/dev/null; then

        "_bl_setting_validate_$MINUS_KEY" "$KEY" "$VALUE" error__ || return 2
    fi
}

# @description Clears settings given its lifetime.
#
# Side effects:
# - Writes `_BL_STATE`.
#
# @arg $1 string Setting lifetime (uppercase).
#
# @exitcode 0 Success.
# @exitcode 1 Invalid lifetime (logged in debug).
# @exitcode 2 `_BL_STATE` is not defined (logged in debug).
bl_setting_clear() {

    local -r SETTING_LIFETIME="$1"

    local state_prefix
    case $SETTING_LIFETIME in

        "${_BL_CONST[SETTING_LIFETIME_RUNTIME]}")
            state_prefix="SETTING_${_BL_CONST[SETTING_LIFETIME_RUNTIME]}"
            ;;

        "${_BL_CONST[SETTING_LIFETIME_SESSION]}")
            state_prefix="SETTING_${_BL_CONST[SETTING_LIFETIME_SESSION]}"
            ;;

        *)
            bl_log_debug \
                "FATAL_SETTING_INVALID_LIFETIME" "$SETTING_LIFETIME"
            return 1
    esac

    if ! declare -p _BL_STATE &>/dev/null; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_STATE"
        return 2
    fi

    for key in "${!_BL_STATE[@]}"; do

        [[ $key == $state_prefix* ]] || continue
        _BL_STATE["$key"]=""
    done
}


# MARK: Validate
# -----------------------------------------------------------------------------
# @section Validators
#
# Functions in this section validate key-value settings depending on its type.

# @description Validates a bool (true or false).
#
# If validation succeeds, error code is empty.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Value.
# @arg $3 string Reference to error code.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_setting_validate_bool() {

    local -r VALUE="$2"
    local -n error___=$3

    error___=""

    if ! [[ $VALUE == true || $VALUE == false ]]; then

        error___=INVALID_BOOL
        return 1
    fi
}

# @description Validates an existing writable directory inside the user's home.
#
# If validation succeeds, error code is empty.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Value.
# @arg $3 string Reference to error code.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_setting_validate_dir() {

    local -r VALUE="$2"
    local -n error___=$3
    
    if [[ -z "$VALUE" ]]; then
        error___="NO_DIR"
        return 1
    fi
    
    if [[ ! -d "$VALUE" ]]; then
        error___="NOT_DIR"
        return 1
    fi

    local -r DIR="$(realpath "$VALUE")"
    local -r REAL_HOME="$(realpath "$HOME")"
    
    if ! [[ $DIR == "$REAL_HOME" || $DIR == "$REAL_HOME"/* ]]; then
        error___="OUT_HOME"
        return 1
    fi
}

# @description Validates an enum according to valid values in `_BL_SETTING_ENUM`.
#
# If validation succeeds, error code is empty.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Value.
# @arg $3 string Reference to error code.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_setting_validate_enum() {

    local -r KEY="$1"
    local -r VALUE="$2"
    local -n error___=$3
    
    error___=""
    local option

    for option in ${_BL_CONST[SETTING_ENUM_"$KEY"]}; do
        [[ $option == "$VALUE" ]] && return 0
    done
    
    error___="INVALID_ENUM"
    return 1
}



# @description Validates an existing bl environment.
#
# If validation succeeds, error code is empty.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Value.
# @arg $3 string Reference to error code.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_setting_validate_env() {

    local -r VALUE="$2"
    local -n error___=$3
    
    if [[ ! -d "$VALUE/${_BL_CONST[DIR_BL]}" ]]; then
        error___="NOT_ENV"
        return 1
    fi
}

# @description Validates a non-existing bl environment.
#
# If validation succeeds, error code is empty.
#
# @arg $1 string Key (uppercase).
# @arg $2 string Value.
# @arg $3 string Reference to error code.
#
# @exitcode 0 Validation succeeds.
# @exitcode 1 Validation fails.
_bl_setting_validate_new_env() {

    local -r VALUE="$2"
    local -n error___=$3
    
    if [[ -d "$VALUE/${_BL_CONST[DIR_BL]}" ]]; then
        error___="NOT_ENV"
        return 1
    fi
}