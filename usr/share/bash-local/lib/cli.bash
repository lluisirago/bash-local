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
                [[ "$key" == LONG_OPTION_BL_* ]] && long_options+=" ${_BL_CONST[$key]}"
            done

            mapfile -t COMPREPLY < <(compgen -W "${long_options}" -- "${current}")
            return 0
        fi

        # Collect bl commands
        local commands=""
        for key in "${!_BL_CONST[@]}"; do
            [[ "$key" == COMMAND_* ]] && commands+=" ${_BL_CONST[$key]}"
        done

        mapfile -t COMPREPLY < <(compgen -W "${commands}" -- "${current}")
        return 0
    fi

    case "${previous}" in

        "${_BL_CONST[COMMAND_INIT]}")

            # Complete long options
            if [[ "${current}" == -* ]]; then

                # Collect init long options
                local long_options=""
                for key in "${!_BL_CONST[@]}"; do
                    [[ "$key" == LONG_OPTION_INIT_* ]] && long_options+=" ${_BL_CONST[$key]}"
                done

                mapfile -t COMPREPLY < <(compgen -W "${long_options}" -- "${current}")
                return 0
            fi

            # Complete directory
            compopt -o nospace -o filenames
            mapfile -t COMPREPLY < <(compgen -d -- "${current}")
            return 0
            ;;
        
        "${_BL_CONST[COMMAND_ADD]}")

            # Complete long options
            if [[ "${current}" == -* ]]; then

                # Collect add long options
                local long_options=""
                for key in "${!_BL_CONST[@]}"; do
                    [[ "$key" == LONG_OPTION_ADD_* ]] && long_options+=" ${_BL_CONST[$key]}"
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
            "${_BL_CONST[OPTION_BL_H]}"|"${_BL_CONST[LONG_OPTION_BL_HELP]}")
                bl-help
                return 0
                ;;
            "${_BL_CONST[OPTION_BL_V]}"|"${_BL_CONST[LONG_OPTION_BL_VERSION]}")
                bl-version
                return 0
                ;;
            -*)
                _bl_log "USAGE_BAD_OPTION" "$1"
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
        "${_BL_CONST[COMMAND_ADD]}")        bl-add "$@";;
        "${_BL_CONST[COMMAND_CONFIG]}")     bl-config "$@";;
        "${_BL_CONST[COMMAND_HELP]}")       bl-help "$@";;
        "${_BL_CONST[COMMAND_INIT]}")       bl-init "$@";;
        "${_BL_CONST[COMMAND_RM]}")         bl-rm "$@";;
        "${_BL_CONST[COMMAND_VERSION]}")    bl-version;;
        *) _bl_log "USAGE_BAD_COMMAND" "$command";;
    esac
}

# MARK: init
bl-init() {

    # Parse options
    local -a args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "${_BL_CONST[OPTION_INIT_H]}"|"${_BL_CONST[LONG_OPTION_INIT_HELP]}")
                bl-help "${_BL_CONST[COMMAND_INIT]}"
                return 0
                ;;
            -*)
                _bl_log "USAGE_BAD_OPTION" "$1"
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
        _bl_log "USAGE_MANY_ARGS"
        return 1
    fi
    _bl_assert_valid_dir "${_BL_CONST[COMMAND_INIT]}" "$ENVIRONMENT" || return 1

    # Initialize environment
    # _bl_cli_init "$ENVIRONMENT" && _bl_log "INFO_INIT" "$BL_PATH" || return $?
    local -r BL_PATH="$ENVIRONMENT/${_BL_CONST[BL_DIR]}"
    [[ ! -d "$BL_PATH" ]] || { _bl_log "FATAL_ALREADY_INIT" "$ENVIRONMENT"; return 1; }
    
    mkdir -p "$BL_PATH/${_BL_CONST[SOURCE_DIR]}"
    echo "1" > "$BL_PATH/${_BL_CONST[MANIFEST_FILENAME]}"
    touch "$BL_PATH/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[LOCAL_FILE]}" \
          "$BL_PATH/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[SCOPED_FILE]}"

    echo "1" > "$BL_PATH/${_BL_CONST[MANIFEST_FILENAME]}"

    _bl_log "INFO_INIT" "$BL_PATH"
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
            "${_BL_CONST[OPTION_ADD_H]}"|"${_BL_CONST[LONG_OPTION_ADD_HELP]}")
                bl-help "${_BL_CONST[COMMAND_ADD]}"
                return 0
                ;;
            # Directory
            "${_BL_CONST[OPTION_ADD_C]}"|"${_BL_CONST[LONG_OPTION_ADD_CWD]}"|\
            "${_BL_CONST[OPTION_ADD_D]}"|"${_BL_CONST[LONG_OPTION_ADD_DIR]}")
                environment=$(realpath -m -- "$2")
                shift
                ;;
            "${_BL_CONST[OPTION_ADD_C]}"=*|"${_BL_CONST[LONG_OPTION_ADD_CWD]}"=*|\
            "${_BL_CONST[OPTION_ADD_D]}"=*|"${_BL_CONST[LONG_OPTION_ADD_DIR]}"=*)
                environment=$(realpath -m -- "${1#*=}")
                ;;
            "${_BL_CONST[OPTION_ADD_C]}"*|"${_BL_CONST[OPTION_ADD_D]}"*)
                environment=$(realpath -m -- "${1:2}")
                ;;
            # Other options
            "${_BL_CONST[LONG_OPTION_ADD_INIT]}") ;;
            "${_BL_CONST[OPTION_ADD_F]}"|"${_BL_CONST[LONG_OPTION_ADD_FORCE]}") ;;
            -*)
                _bl_log "USAGE_BAD_OPTION" "$1"
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



    _bl_core_append_to_manifest "$environment" real_names real_scopes real_kinds real_starts real_ends
}

# MARK: rm
bl-rm() {
    
    local -a names lines scopes kinds starts ends
    names+=("local_test0")
    _bl_manifest_collect_traits_by_name "$PWD" names lines scopes kinds starts ends
    _bl_core_remove_from_manifest "$PWD" names lines
}

# MARK: config
bl-config() {
    # Como git-config
    echo "config"
}

# MARK: version
bl-version() {

    [[ -n "${_BL_CONST[VERSION]:-}" ]] || { _bl_log "FATAL_NO_VERSION"; return 1; }
    
    echo -e "bl version ${_BL_CONST[VERSION]}"
}

# MARK: help
bl-help() {

    if [[ $# -lt 1 ]]; then
        _bl_log "HELP"
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