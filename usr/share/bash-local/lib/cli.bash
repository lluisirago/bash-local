#!/user/bin/env bash

# MARK: Completion
_bl_cli_completion() {
   
    local current="${COMP_WORDS[COMP_CWORD]}"
    local previous="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Complete commands
    if [[ ${COMP_CWORD} -eq 1 ]]; then

        # Complete long options
        if [[ "${current}" == -* ]]; then

            # Collect bl long options
            local long_options=""
            for key in "${!_BL_CONST[@]}"; do
                [[ "$key" == BL_LONG_OPTION_* ]] && long_options+=" ${_BL_CONST[$key]}"
            done

            mapfile -t COMPREPLY < <(compgen -W "${long_options}" -- "${current}")
            return 0
        fi

        # Collect bl commands
        local commands=""
        for key in "${!_BL_CONST[@]}"; do
            [[ "$key" == *_COMMAND ]] && commands+=" ${_BL_CONST[$key]}"
        done

        mapfile -t COMPREPLY < <(compgen -W "${commands}" -- "${current}")
        return 0
    fi

    case "${previous}" in

        "${_BL_CONST[INIT_COMMAND]}")

            # Complete long options
            if [[ "${current}" == -* ]]; then

                # Collect init long options
                local long_options=""
                for key in "${!_BL_CONST[@]}"; do
                    [[ "$key" == INIT_LONG_OPTION_* ]] && long_options+=" ${_BL_CONST[$key]}"
                done

                mapfile -t COMPREPLY < <(compgen -W "${long_options}" -- "${current}")
                return 0
            fi

            # Complete directory
            compopt -o nospace -o filenames
            mapfile -t COMPREPLY < <(compgen -d -- "${current}")
            return 0
            ;;
        
        "${_BL_CONST[ADD_COMMAND]}")

            # Complete long options
            if [[ "${current}" == -* ]]; then

                # Collect add long options
                local long_options=""
                for key in "${!_BL_CONST[@]}"; do
                    [[ "$key" == ADD_LONG_OPTION_* ]] && long_options+=" ${_BL_CONST[$key]}"
                done

                mapfile -t COMPREPLY < <(compgen -W "${long_options}" -- "${current}")
                return 0
            fi
            ;;
            
        *)
            compopt -o default
            COMPREPLY=()
            ;;
    esac
}
complete -F _bl_cli_completion bl


# MARK: bl
bl() {

    if [[ $# -lt 1 ]]; then
        bl-help
        return 1
    fi

    local command
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "${_BL_CONST[BL_OPTION_H]}"|"${_BL_CONST[BL_LONG_OPTION_HELP]}")
                bl-help
                return 0
                ;;
            "${_BL_CONST[BL_OPTION_V]}"|"${_BL_CONST[BL_LONG_OPTION_VERSION]}")
                bl-version
                return 0
                ;;
            -*)
                bl_log "USAGE_INVALID_OPTION" "$1"
                return 1
                ;;
            *)
                command="$1"
                shift
                break
                ;;
        esac
        shift
    done

    case "$command" in
        "${_BL_CONST[ADD_COMMAND]}")        bl-add "$@";;
        "${_BL_CONST[CONFIG_COMMAND]}")     bl-config "$@";;
        "${_BL_CONST[HELP_COMMAND]}")       bl-help "$@";;
        "${_BL_CONST[INIT_COMMAND]}")       bl-init "$@";;
        "${_BL_CONST[RM_COMMAND]}")         bl-rm "$@";;
        "${_BL_CONST[VERSION_COMMAND]}")    bl-version;;
        *) bl_log "USAGE_INVALID_COMMAND" "$command";;
    esac
}

# MARK: init
bl-init() {

    # Parse options
    local -a args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "${_BL_CONST[INIT_OPTION_H]}"|"${_BL_CONST[INIT_LONG_OPTION_HELP]}")
                bl-help "${_BL_CONST[INIT_COMMAND]}"
                return 0
                ;;
            -*)
                bl_log "USAGE_INVALID_OPTION" "$1"
                return 1
                ;;
            *)  
                args+=("$1")
                ;;
        esac
        shift
    done
    
    # Parse environment path
    if [[ "${#args[@]}" -eq 0 ]]; then
        local -r ENVIRONMENT="$PWD"
    elif [[ "${#args[@]}" -eq 1 ]]; then
        local -r ENVIRONMENT=$(realpath -m -- "${args[0]}")
    else
        bl_log "USAGE_MANY_ARGS"
        return 1
    fi
    _bl_assert_valid_dir "${_BL_CONST[INIT_COMMAND]}" "$ENVIRONMENT" || return 1

    # Initialize environment
    # _bl_cli_init "$ENVIRONMENT" && bl_log "INFO_INIT" "$BL_PATH" || return $?
    local -r BL_PATH="$ENVIRONMENT/${_BL_CONST[DIR_BL]}"
    [[ ! -d "$BL_PATH" ]] || { bl_log "FATAL_ALREADY_INIT" "$ENVIRONMENT"; return 1; }
    
    mkdir -p "$ENVIRONMENT/${_BL_CONST[DIR_SOURCE]}"
    echo "1" > "$$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"
    touch "$ENVIRONMENT/${_BL_CONST[PATH_SOURCE_LOCAL]}" \
          "$ENVIRONMENT/${_BL_CONST[PATH_SOURCE_SCOPED]}"

    echo "1" > "$ENVIRONMENT/${_BL_CONST[PATH_MANIFEST]}"

    bl_log "INFO_INIT" "$BL_PATH"
}

# MARK: show
bl-show() {

    return 0
}

# MARK: add
bl-add() {

    # Options:   [-C <dir> | --cwd <dir> | -d <dir> | --dir <dir>] where to add the elements
    #            [--init] create the environment if not exists
    #            [-f | --force] overwrite elements if exist
    #
    # Syntax:   [scope:][kind:]name[=[value | @file]]
    #
    # Usage:    bl add (local:var: by default)DB_USER=admin \
    #           local:alias:deploy="git push" \
    #           scoped:var:SECRET_KEY=xyz \
    #           local:func:foo="echo 'Hello World'"
    #
    # Cases:  [scope:][kind:]name=value
    #         [scope:][kind:]name (opens editor, nano by default)
    #         [scope:][kind:]name=@file
    #
    # Could be used reading from stdin:
    #   cat file | bl add
    
    # Parse options
    local environment="$PWD"
    local -a args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "${_BL_CONST[ADD_OPTION_H]}"|"${_BL_CONST[ADD_LONG_OPTION_HELP]}")
                bl-help "${_BL_CONST[ADD_COMMAND]}"
                return 0
                ;;
            # Directory
            "${_BL_CONST[ADD_OPTION_C]}"|"${_BL_CONST[ADD_LONG_OPTION_CWD]}"|\
            "${_BL_CONST[ADD_OPTION_D]}"|"${_BL_CONST[ADD_LONG_OPTION_DIR]}")
                environment=$(realpath -m -- "$2")
                shift
                ;;
            "${_BL_CONST[ADD_OPTION_C]}"=*|"${_BL_CONST[ADD_LONG_OPTION_CWD]}"=*|\
            "${_BL_CONST[ADD_OPTION_D]}"=*|"${_BL_CONST[ADD_LONG_OPTION_DIR]}"=*)
                environment=$(realpath -m -- "${1#*=}")
                ;;
            "${_BL_CONST[ADD_OPTION_C]}"*|"${_BL_CONST[ADD_OPTION_D]}"*)
                environment=$(realpath -m -- "${1:2}")
                ;;
            # Other options
            "${_BL_CONST[ADD_LONG_OPTION_INIT]}") ;;
            "${_BL_CONST[ADD_OPTION_F]}"|"${_BL_CONST[ADD_LONG_OPTION_FORCE]}") ;;
            -*)
                bl_log "USAGE_INVALID_OPTION" "$1"
                return 1
                ;;
            *)
                args+=("$1")
                ;;
        esac
        shift
    done
    _bl_assert_valid_dir "$1" "$environment" || return 1


    #echo "$environment"

    # Add each argument (element)
    # Check with a regular expression
    # Validate each part of the argument (scope, kind, name, etc)
    # _bl_core_add_element scope kind name ...
    local -a names lines scopes starts ends
    names+=("local_test0")
    scopes+=("local")
    kinds+=("alias")
    starts+=("0")
    ends+=("0")
    names+=("local_test1")
    scopes+=("local")
    kinds+=("alias")
    starts+=("1")
    ends+=("1")
    names+=("scoped_test0")
    scopes+=("scoped")
    kinds+=("alias")
    starts+=("0")
    ends+=("0")
    names+=("scoped_test1")
    scopes+=("scoped")
    kinds+=("alias")
    starts+=("1")
    ends+=("1")


    _bl_manifest_collect_traits_by_name "$PWD" names lines__ scopes__ kinds__ starts__ ends__
    for (( _i_ = 0; _i_ < ${#names[@]}; _i_++ )); do

        if [[ -z "${lines__[_i_]+x}" ]]; then
            real_names[_i_]="${names[_i_]}"
            real_scopes[_i_]="${scopes[_i_]}"
            real_kinds[_i_]="${kinds[_i_]}"
            real_starts[_i_]="${starts[_i_]}"
            real_ends[_i_]="${ends[_i_]}"
        fi
    done



    _bl_manifest_append_by_traits "$environment" real_names real_scopes real_kinds real_starts real_ends
}

# MARK: rm
bl-rm() {
    
    local -a names lines scopes kinds starts ends
    names+=("local_test0")
    _bl_manifest_collect_traits_by_name "$PWD" names linenos scopes kinds starts ends
    _bl_manifest_remove_by_lineno "$PWD" linenos
}

# MARK: config
bl-config() {
    # Como git-config
    echo "config"
}

# MARK: version
bl-version() {

    [[ -n "${_BL_CONST[VERSION]:-}" ]] || { bl_log "FATAL_NO_VERSION"; return 1; }
    
    echo -e "bl version ${_BL_CONST[VERSION]}"
}

# MARK: help
bl-help() {

    if [[ $# -lt 1 ]]; then

        local -r usage="usage: bl [-v | --version] [-h | --help] <command> [<args>]"
        local -r commands=$(
            {
                echo "  init:Initialize a new environment"
                echo "  add:Add aliases, functions and/or variables to an environment"
                echo "  rm:Remove elements from an environment"
            } | column -t -s ':'
        )
        echo "$usage"
        echo
        echo "These are common bl commands:"
        echo
        echo "$commands"
        return 0
    fi

    man "bl $1"    
}

bl-show() {

    local -a names lines scopes starts ends
    names+=("local")
    names+=("scoped")
    names+=("foo")
    names+=("version")
    _bl_core_collect_from_manifest_by_name "$PWD" names lines scopes starts ends

    for (( _i_ = 0; _i_ < "${#names[@]}"; _i_++ )); do
        echo "${names[_i_]}: (${lines[_i_]}) ${scopes[_i_]} ${starts[_i_]} ${ends[_i_]}"
    done
}

# MARK: Args
# -----------------------------------------------------------------------------
# @section Arguments parsing
#
# Functions in this section implement arguments parsing fo functions above.

# @description Parses a set of command-line arguments, sets detected options, 
# and returns remaining arguments.
#
# @arg $1 array Reference to arguments array.
# @arg $2... Arguments to process (typically "$@").
#
# @exitcode 0 Success.
# @exitcode 1 Argument parsing failed (logged / logged in debug).
# @exitcode 2 Internal error in set operation (logged in debug).
# @exitcode 3 Argument validation failed (logged).
_bl_cli_parse_arguments() {

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
            _bl_cli_parse_option "$arg" "$next_arg" \
                option value args_consumed || return 1
            
            local key="${_BL_CONST["SETTING_OF_$option"]}"
            bl_setting_set RUNTIME "$key" "$value" error

            case $? in
                0) ;;
                1) return 2;;
                2) bl_log "FATAL_$error" "$value" "$option"; return 3;;
                3) return 2;;
                4) return 2;;
            esac
            
        else
            args_+=("$arg")
            args_consumed=1
        fi

        shift "$args_consumed"
    done
}

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
# @exitcode 1 Exact search failed (logged / logged in debug).
# @exitcode 2 Prefix search failed (logged / logged in debug).
_bl_cli_parse_option() {

    local -r ARG="$1"
    local -r NEXT_ARG="$2"
    local -n option_=$3
    local -n value_=$4
    local -n args_consumed_=$5

    _bl_cli_parse_option_exact_match "$ARG" "$NEXT_ARG" \
        option_ value_ args_consumed_

    case $? in
        0) return 0;;
        1) return 1;;
        2) ;; # No exact match; continue with prefix matching.
    esac

    _bl_cli_parse_option_prefix_match "$ARG" \
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
# @exitcode 2 Option not found (logged).
_bl_cli_parse_option_exact_match() {

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
_bl_cli_parse_option_prefix_match() {

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
        if (( ${#aux_option} > ${#option_} )); then
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

# @description Normalizes a value depending on option type. Boolean options with
# empty value are set to 'true'.
#
# Side effects:
# - Reads `_BL_CONST`.
#
# @arg $1 string Reference to option.
# @arg $2 string Reference to value.
#
# @exitcode 0 Success.
# @exitcode 1 `_BL_CONST["SETTING_OF_<option>"]` is not defined or is empty
#             (logged in debug).
_bl_cli_get_type() {

    local -r OPTION=$1
    local -n setting_type_=$2

    local setting="${_BL_CONST["SETTING_OF_$OPTION"]}"

    if ! [[ -n "${_BL_CONST["SETTING_TYPE_$setting"]:-}" ]]; then
        bl_log_debug "FATAL_MISSING_VARIABLE" "_BL_CONST[SETTING_TYPE_$setting]"
        return 1
    fi

    setting_type_="${_BL_CONST["SETTING_TYPE_$setting"]}"
}