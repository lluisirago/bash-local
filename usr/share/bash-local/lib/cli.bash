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
                _bl_log "INFO_BAD_OPTION" "$1"
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

    [[ -z "$command" ]] && return 0

    case "$command" in
        "${_BL_CONST[COMMAND_ADD]}")        bl-add "$@";;
        "${_BL_CONST[COMMAND_CONFIG]}")     bl-config "$@";;
        "${_BL_CONST[COMMAND_HELP]}")       bl-help "$@";;
        "${_BL_CONST[COMMAND_INIT]}")       bl-init "$@";;
        "${_BL_CONST[COMMAND_RM]}")         bl-rm "$@";;
        "${_BL_CONST[COMMAND_VERSION]}")    bl-version;;
        *) _bl_log "INFO_BAD_COMMAND" "$command";;
    esac
}

# MARK: init
bl-init() {

    # Parse arguments
    local -a args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "${_BL_CONST[OPTION_INIT_H]}"|"${_BL_CONST[LONG_OPTION_INIT_HELP]}")
                bl-help "${_BL_CONST[COMMAND_INIT]}"
                return 0
                ;;
            -*)
                _bl_log "INFO_BAD_OPTION" "$1"
                return 1
                ;;
            *)  
                args+=("$1")
                ;;
        esac
        shift
    done
    [[ "${#args[@]}" -lt 2 ]] || { _bl_log "INFO_MANY_ARGS"; return 1; }

    if [[ "${#args[@]}" -gt 0 ]]; then
        local -r PATH=$(realpath -m -- "${args[0]}")
    else
        local -r PATH="$PWD"
    fi
    _bl_assert_valid_dir "${_BL_CONST[COMMAND_INIT]}" "$PATH" || return 1

    # Initialize environment
    local -r BL_PATH="$PATH/${_BL_CONST[BL_DIR]}"
    [[ ! -d "$BL_PATH" ]] || { _bl_log "FATAL_ALREADY_INIT" "$PATH"; return 1; }

    mkdir -p "$BL_PATH/${_BL_CONST[SOURCE_DIR]}"
    touch "$BL_PATH/${_BL_CONST[MANIFEST_FILE]}" \
          "$BL_PATH/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[LOCAL_FILE]}" \
          "$BL_PATH/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[SCOPED_FILE]}"

    echo "Initialized empty environment in '$BL_PATH'"
}

# MARK: show
bl-show() {

    return 0
}

# MARK: add
bl-add() {

    # Options:   [-C <dir> | --cwd <dir> | -d <dir> | --dir <dir>] where to add the elements
    #            [--init] create the environment without asking
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
    
    local path="$PWD"
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
                path=$(realpath -m -- "$2")
                shift
                ;;
            "${_BL_CONST[OPTION_ADD_C]}"=*|"${_BL_CONST[LONG_OPTION_ADD_CWD]}"=*|\
            "${_BL_CONST[OPTION_ADD_D]}"=*|"${_BL_CONST[LONG_OPTION_ADD_DIR]}"=*)
                path=$(realpath -m -- "${1#*=}")
                ;;
            "${_BL_CONST[OPTION_ADD_C]}"*|"${_BL_CONST[OPTION_ADD_D]}"*)
                path=$(realpath -m -- "${1:2}")
                ;;
            # Other options
            "${_BL_CONST[LONG_OPTION_ADD_INIT]}") ;;
            "${_BL_CONST[OPTION_ADD_F]}"|"${_BL_CONST[LONG_OPTION_ADD_FORCE]}") ;;
            -*)
                _bl_log "INFO_BAD_OPTION" "$1"
                return 1
                ;;
            *)
                args+=("$1")
                ;;
        esac
        shift
    done
    _bl_assert_valid_dir "$1" "$path" || return 1


    echo "$path"

    # Add each argument (element)
    # Check with a regular expression
    # Validate each part of the argument (scope, kind, name, etc)
    # _bl_core_add_element scope kind name ...
}

# MARK: rm
bl-rm() {
    echo "rm"
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