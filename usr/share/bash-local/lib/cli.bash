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
                bl_log "USAGE_BAD_OPTION" "$1"
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
        *) bl_log "USAGE_BAD_COMMAND" "$command";;
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
                bl_log "USAGE_BAD_OPTION" "$1"
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
                bl_log "USAGE_BAD_OPTION" "$1"
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
    _bl_manifest_collect_traits_by_name "$PWD" names lines scopes kinds starts ends
    _bl_manifest_remove_by_lines "$PWD" names lines
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