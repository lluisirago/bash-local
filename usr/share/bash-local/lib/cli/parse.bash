#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file parse.bash
#
# @brief CLI arguments parser implementation.

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public funtions
#
# Functions in this section are intended to be called by CLI module.

# @description Parses a set of command-line arguments, sets detected options, 
# and returns remaining arguments.
#
# @arg $1 array Reference to arguments array.
# @arg $2... Arguments to process (typically "$@").
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 Argument parsing failed (logged).
bl_parse_arguments() {

    local -n args_=$1
    shift

    local args_consumed
    local keep_parsing_options=true
    while [[ $# -gt 0 ]]; do

        local arg="$1"
        local next_arg="${2-}"
        local error=""

        if [[ $arg == "--" ]]; then

            keep_parsing_options=false
            args_consumed=1

        elif [[ $keep_parsing_options == true && $arg == "-"* ]]; then
            
            local option value
            _bl_parse_option "$arg" "$next_arg" \
                option value args_consumed || return
            
            local key="${_BL_CONST["SETTING_OF_$option"]}"
            bl_setting_set RUNTIME "$key" "$value" error
            case $? in
                0) ;;
                1) return 1;;
                2)
                    bl_log "FATAL_INVALID_OPTION" "$option" "$value" "$error" 
                    return 2
                    ;;
                3) return 1;;
                4) return 1;;
            esac
            
        else
            args_+=("$arg")
            args_consumed=1
        fi

        shift "$args_consumed"
    done
}


# MARK: Private
# -----------------------------------------------------------------------------
# @section Private funtions
#
# Functions in this section are not intended to be called by other modules.

# @description Parses a single command-line option and its value.
#
# Supported formats:
#  --option
#  --option=value
#  --option value
#  -o
#  -ovalue
#  -o=value
#  -o value
#
# Grouped options like '-xyz' are not supported.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Argument given by user.
# @arg $2 string Next argument.
# @arg $3 string Reference to option.
# @arg $4 string Reference to value.
# @arg $5 string Reference to number of consumed arguments.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
# @exitcode 2 Search failed (logged).
_bl_parse_option() {

    local -r ARG="$1"
    local -r NEXT_ARG="$2"
    local -n option_=$3
    local -n value_=$4
    local -n args_consumed_=$5

    _bl_parse_option_exact_match "$ARG" "$NEXT_ARG" \
        option_ value_ args_consumed_

    case $? in
        0) return 0;;
        1) return 1;;
        2) ;; # No exact match; continue with prefix matching.
    esac

    _bl_parse_option_prefix_match "$ARG" \
        option_ value_ args_consumed_ || return 2
}

# @description Parses a single command-line option and its value by exact
# match. Efficient.
#
# Targeted formats:
#  --option
#  --option value
#  -o
#  -o value
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Argument given by user.
# @arg $2 string Next argument.
# @arg $3 string Reference to option.
# @arg $4 string Reference to value.
# @arg $5 string Reference to number of consumed arguments.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST` is not defined or is empty (logged in debug).
# @exitcode 2 Option not found.
_bl_parse_option_exact_match() {

    local -r ARG="$1"
    local -r NEXT_ARG="$2"
    local -n option__=$3
    local -n value__=$4
    local -n args_consumed__=$5

    option__=""
    value__=""
    args_consumed__=0

    if ! declare -p _BL_CONST &>/dev/null; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST"
        return 1
    fi

    [[ -n "${_BL_CONST["SETTING_OF_$ARG"]:-}" ]] || return 2

    option__="$ARG"

    local setting="${_BL_CONST["SETTING_OF_$option__"]}"
        
    if ! [[ -n "${_BL_CONST["SETTING_TYPE_$setting"]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SETTING_TYPE_$setting]"
        return 1
    fi
    local setting_type="${_BL_CONST["SETTING_TYPE_$setting"]}"

    if [[ $setting_type == "bool" ]]; then

        value__=true
        args_consumed__=1
    
    elif [[ -n "$NEXT_ARG" && $NEXT_ARG != "-"* ]]; then

        value__="$NEXT_ARG"
        args_consumed__=2

    else
        
        value__=""
        args_consumed__=1
    fi
}

# @description Parses a single command-line option and its value by prefix
# match. Inefficient.
#
# Targeted formats:
#  --option=value
#  -ovalue
#  -o=value
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Argument given by user.
# @arg $2 string Reference to option.
# @arg $3 string Reference to value.
# @arg $4 string Reference to number of consumed arguments.
#
# @exitcode 0 Success.
# @exitcode 1 Option not found (logged).
_bl_parse_option_prefix_match() {

    local -r ARG="$1"
    local -n option__=$2
    local -n value__=$3
    local -n args_consumed__=$4

    option__=""
    value__=""
    args_consumed__=0

    local key aux_option aux_value aux_args_consumed
    for key in "${!_BL_CONST[@]}"; do

        [[ $key == "SETTING_OF_"*  ]] || continue

        aux_option="${key#SETTING_OF_}"

        if [[ $ARG == "$aux_option="* ]]; then
            aux_value="${ARG#*=}"
            aux_args_consumed=1

        elif [[ $ARG == "$aux_option"* && $aux_option != "--"* ]]; then

            aux_value="${ARG#"$aux_option"}"
            aux_args_consumed=1

        else
            continue
        fi

        # Keep longest matching option
        if (( ${#aux_option} > ${#option__} )); then
            option__="$aux_option"
            value__="$aux_value"
            args_consumed__="$aux_args_consumed"
        fi
    done

    if [[ -z $option__ ]]; then
        bl_log "USAGE_INVALID_OPTION" "$ARG"
        return 1
    fi
}