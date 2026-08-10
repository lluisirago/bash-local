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
    echo "INIT $1"
    return 0
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

    true
}

# MARK: add
bl-add() {

    # Options:   [ -C <dir> | --cwd <dir> | -d <dir> | --dir <dir> ] where to add the elements
    #            [ --init ] create the environment if does not exist
    #            [ -f | --force ] overwrite elements if exist
    #            [ --atomic ] if one validation fails, no element is added
    #
    # Syntax: [scope:][kind:]name[=<source>]
    #
    # Where <source> is one of:
    #  - text        Inline value
    #  - @file       Read from file
    #  - -           Read from stdin
    #
    # If omitted opens the editor (nano by default).
    #
    # Usage:    bl add (local:var: by default)DB_USER=admin \
    #           local:alias:deploy="git push" \
    #           scoped:var:SECRET_KEY=xyz \
    #           func:foo="echo 'Hello World'"
    
    local arguments atomic env force help init verbose version
    _bl_cli_run bl_parse_arguments arguments "$@" || return    
    _bl_cli_run bl_add_take_in atomic env force help init verbose version
    case $? in
        1) return 1;;
        2) return 2;;
        3) return 0;;
    esac
    
    local stdin=""
    [[ ! -t 0 ]] && stdin=$(cat)

    _bl_cli_run bl_add_main "$atomic" "$env" "$force" "$stdin" arguments || return
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

# MARK: Auxiliar
# -----------------------------------------------------------------------------
# @section Auxiliar functions
_bl_cli_run() {

    local retval
    "$@"
    retval=$?
    if (( retval != 0 )); then
        bl_setting_clear "${_BL_CONST[SETTING_LIFETIME_RUNTIME]}"
    fi
    return "$retval"
}

_bl_cli_resolve() {

    local -r KEY="$1"
    local -n value=$2

    local -r TYPE="${_BL_CONST["SETTING_TYPE_$KEY"]}"
    
    local error
    bl_setting_resolve "$KEY" value error
    case $? in
        0) [[ $TYPE == "dir" ]] && value="$(realpath "$value")"; return 0;;
        1) return 1;;
        2) bl_log "FATAL_INVALID_ENV_VAR" "$KEY" "$error"; return 2;;
        3) [[ $TYPE == "dir" ]] && value="$(realpath "$value")"; bl_log "FATAL_$error" "$value"; return 2;;
        4) return 1;;
    esac
}

# MARK: Modules
# -----------------------------------------------------------------------------
# @section Source modules
source "$(dirname "${BASH_SOURCE[0]}")/parse.bash"
source "$(dirname "${BASH_SOURCE[0]}")/add.bash"