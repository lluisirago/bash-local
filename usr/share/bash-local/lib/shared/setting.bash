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
# @exitcode 1 Internal validation error.
# @exitcode 2 Resolved using fallback after ignoring an invalid environment
#             variable.
# @exitcode 3 Unknown setting.
bl_setting_resolve() {

    local -r KEY="$1"    
    local -n value_=$2
    local -n env_var_error=$3

    value_=""

    # 1. CLI option
    if [[ -n "${_BL_STATE["SETTING_RUNTIME_$KEY"]:-}" ]]; then
        
        value_="${_BL_STATE["SETTING_RUNTIME_$KEY"]}"
        return 0
    fi

    # 2. Environment variable
    local -r KEY_ENV_VAR="BL_$KEY"
    local -i status_env_var=0

    if [[ -v $KEY_ENV_VAR ]]; then

        bl_setting_validate "$KEY" "${!KEY_ENV_VAR}" env_var_error
        case $? in
            0)  value_="${!KEY_ENV_VAR}"; return 0;;
            1)  return 1;;
            2)  status_env_var=2;;
        esac
    fi

    # 3. Configuration
    if [[ -n "${_BL_STATE["SETTING_SESSION_$KEY"]:-}" ]]; then

        value_="${_BL_STATE["SETTING_SESSION_$KEY"]}"
        return $status_env_var
    fi

    # 4. Default value
    if [[ -n "${_BL_CONST["SETTING_DEFAULT_$KEY"]:-}" ]]; then

        value_="${_BL_CONST["SETTING_DEFAULT_$KEY"]}"
        return $status_env_var
    fi

    bl_log_debug "FATAL_INVALID_SETTING" "${KEY,,}" # (lowercase)
    return 3
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
# @exitcode 1 Given key type is not defined in `_BL_CONST`.
# @exitcode 2 Validation fails.
# @exitcode 3 Invalid lifetime.
# @exitcode 4 Given setting is not defined in `_BL_STATE`.
bl_setting_set() {

    local -r SETTING_LIFETIME="$1"
    local -r KEY="$2"
    local -r VALUE="$3"
    local -n error_=$4
    
    bl_setting_validate "$KEY" "$VALUE" error_ || return
    
    local state_key
    case $SETTING_LIFETIME in

        "${_BL_CONST[SETTING_LIFETIME_RUNTIME]}")
            state_key="SETTING_RUNTIME_${KEY}"
            ;;

        "${_BL_CONST[SETTING_LIFETIME_SESSION]}")
            state_key="SETTING_SESSION_${KEY}"
            ;;

        *)
            bl_log_debug \
                "FATAL_SETTING_SET_INVALID_LIFETIME" "$SETTING_LIFETIME"
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
# @exitcode 1 Given key type is not defined in `_BL_CONST`.
# @exitcode 2 Validation fails.
bl_setting_validate() {

    local -r KEY="$1"
    local -r VALUE="$2"
    local -n error__=$3

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
    if declare -F "_bl_setting_validate_$MINUS_KEY" >/dev/null; then

        "_bl_setting_validate_$MINUS_KEY" "$VALUE" error__ || return 2
    fi
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

        error___=NO_BOOL
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
        error___="NOT_A_DIR"
        return 1
    fi
    
    if [[ ! -w "$VALUE" ]]; then
        error___="NO_PERM"
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