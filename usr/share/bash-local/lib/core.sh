#!/bin/bash
# -----------------------------------------------------------------------------
# @file core.sh
#
# @brief Internal core API.
# @description Contains all the functions needed to synchronize the bash-local
# environments with the current directory. Not intended to be called directly
# by users.


# MARK: Envs
# -----------------------------------------------------------------------------
# @section Environments
# @description Environments' arrays must be refreshed on each execution.
# 
# Note that *current* and *previous* describe the active environments at a
# given directory state and *old* and *new* represent environments to be
# removed from or added to the current state.
#
# Also note that *unload* or *load* refers to an enviroment and *remove* or
# *add* to an element.

# @description Calculates the current environments.
#
# Does it by searching a `bl` directory in PWD (Path Working Directory)
# parents and storing them in `_BL_STATE_CURRENT_ENVIRONMENTS`. The function
# does nothing but clear the array if the PWD is not inside the HOME directory.
#
# @noargs
# @see Used in [_bl_core_refresh_environments](#_bl_core_refresh_environments)
_bl_core_refresh_current_environments_array() {

    _BL_STATE_CURRENT_ENVIRONMENTS=()
    [[ $PWD == "$HOME"* ]] || return

    local dir=$PWD
    while [[ $dir != "$HOME" ]]; do

        # Store if has a `bl` directory and remove the last segment (e.g. 
        # remove `/segment` from `$HOME/segment`)
        [[ -d "$dir/${_BL_CONST[BL_DIR]}" ]] && _BL_STATE_CURRENT_ENVIRONMENTS+=("$dir")
        dir=${dir%/*}
    done

    return 0
}

# @description Updates the previous and current environments' arrays.
# Sets the current environments as previous and calculates the current ones.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_refresh_environments_arrays() {

    _BL_STATE_PREVIOUS_ENVIRONMENTS=("${_BL_STATE_CURRENT_ENVIRONMENTS[@]}")
    _bl_core_refresh_current_environments_array

    echo "Previous environments:" "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"
    echo "Current environments:" "${_BL_STATE_CURRENT_ENVIRONMENTS[@]}"

    return 0
}

# @description Gets the previous environments which are not current.
#
# @arg $1 array Reference to the old environments' array.
# @see Used in [_bl_core_unload_environments](#_bl_core_unload_environments)
_bl_core_resolve_prunable_environments() {
    
    local -n old_environments_=$1

    local -A current_environments=()
    local environment

    # Load the current environments into the map
    for environment in "${_BL_STATE_CURRENT_ENVIRONMENTS[@]}"; do
        current_environments["$environment"]=1
    done

    # Get the previous environments not in the map
    for environment in "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"; do
        [[ ! ${current_environments["$environment"]+x} || "$environment" == "${_BL_STATE[PPD]}" ]] && old_environments_+=("$environment")
    done

    echo "Old environments: " "${old_environments[@]}"

    return 0
}

# @description Gets the current environments which are not previous.
#
# @arg $1 array Reference to the new environments' array.
# @see Used in [_bl_core_load_environments](#_bl_core_load_environments)
_bl_core_resolve_applicable_environments() {

    local -n new_environments_=$1

    local -A previous_environments=()
    local environment

    # Load the previous environments into the map
    for environment in "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"; do
        previous_environments["$environment"]=1
    done

    # Get the current environments not in the map
    for environment in "${_BL_STATE_CURRENT_ENVIRONMENTS[@]}"; do
        [[ ! ${previous_environments["$environment"]+x} || "$environment" == "$PWD" ]] && new_environments_+=("$environment")
    done

    return 0
}

# @description Gets all the elements from the old environments, filtered by
# kind.
#
# A list of these elements is stored at the `manifest` file located inside each
# environment's `.bl` directory. This function reads the manifests in order to
# get the aliases, functions and variables.
#
# @arg $1 array Constant reference to the old environments' array.
# @arg $2 array Reference to the aliases' array.
# @arg $3 array Reference to the functions' array.
# @arg $4 array Reference to the variables' array.
# @see Used in [_bl_core_unload_environments](#_bl_core_unload_environments)
_bl_core_collect_removable_elements() {

    local -rn OLD_ENVIRONMENTS=$1
    local -n aliases_=$2
    local -n functions_=$3
    local -n variables_=$4

    local env
    for env in "${OLD_ENVIRONMENTS[@]}"; do

        # Decide if local elements must be collected
        if [[ "$env" == "${_BL_STATE[PPD]}" ]]; then
            local is_env_root=true
        else
            local is_env_root=false
        fi
        
        # Extract aliases, functions and variables from the manifest
        local line
        while IFS= read -r line; do
 
            [[ -z "$line" ]] && continue
            
            # `line` is a section header (e.g. [local.aliases])
            if [[ "$line" =~ ${_BL_CONST[SECTION_REGEX]} ]]; then

                local section="${line:1:-1}"
                local scope="${section%%.*}"
                local kind="${section##*.}"

            # `line` is an element
            elif [[ ("$scope" == "${_BL_CONST[SCOPE_LOCAL]}" && "$is_env_root" == true) ||
                     "$scope" == "${_BL_CONST[SCOPE_SCOPED]}" ]]; then
                
                case "$kind" in
                    "${_BL_CONST[KIND_ALIASES]}") aliases_+=("$line") ;;
                    "${_BL_CONST[KIND_FUNCTIONS]}") functions_+=("$line") ;;
                    "${_BL_CONST[KIND_VARIABLES]}") variables_+=("$line") ;;
                esac
            fi
        done < "$env/${_BL_CONST[BL_DIR]}/${_BL_CONST[MANIFEST_FILE]}"
    done

    echo "Old aliases: " "${aliases_[@]}"
    echo "Old functions: " "${functions_[@]}"
    echo "Old variables: " "${variables_[@]}"

    return 0
}


# MARK: Unload
# -----------------------------------------------------------------------------
# @section Unload stage
# @description Old environments are unloaded at every `cd` execution (i.e.
# all the elements from each old environment are removed).

# @description Removes the given elements.
#
# @arg $1 array Constant reference to the aliases' array.
# @arg $2 array Constant reference to the functions' array.
# @arg $3 array Constant reference to the variables' array.
# @see Used in [_bl_core_unload_environments](#_bl_core_unload_environments)
_bl_core_remove_elements() {

    local -rn ALIASES=$1
    local -rn FUNCTIONS=$2
    local -rn VARIABLES=$3

    local element

    for element in "${ALIASES[@]}"; do
        unalias "$element" 2>/dev/null
    done

    for element in "${FUNCTIONS[@]}"; do
        unset -f "$element" 2>/dev/null
    done

    for element in "${VARIABLES[@]}"; do
        unset "$element" 2>/dev/null
    done

    return 0
}

# @description Unloads the old environments (i.e. those exited at the `cd`
# execution).
#
# The function does nothing if the `PPD` (Path Previous Directory) is not inside
# the `HOME` directory.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_prune_environments() {
    
    [[ ${_BL_STATE[PPD]} == $HOME* ]] || return

    local -a old_environments aliases functions variables
    
    _bl_core_resolve_prunable_environments old_environments
    _bl_core_collect_removable_elements old_environments aliases functions variables
    _bl_core_remove_elements aliases functions variables

    return 0
}


# MARK: Load
# -----------------------------------------------------------------------------
# @section Load stage
# @description New environments are loaded at every `cd` execution (i.e.
# all the elements from each new environment are added).

_bl_core_source_in_scope_elements() {

    local -rn NEW_ENVIRONMENTS=$1

    local env
    for env in "${NEW_ENVIRONMENTS[@]}"; do

        if [[ "$env" == "$PWD" ]]; then
            source "$env/${_BL_CONST[BL_DIR]}/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[LOCAL_FILE]}"
            echo "source $env/${_BL_CONST[BL_DIR]}/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[LOCAL_FILE]}"
        fi
        # Estoy cargando siempre scoped pero no hace falta, cuando paso de bash.../a a bash.../ solo necesito cargar local
        # porque scoped ya estaba cargado
        source "$env/${_BL_CONST[BL_DIR]}/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[SCOPED_FILE]}"
        echo "source $env/${_BL_CONST[BL_DIR]}/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[SCOPED_FILE]}"
    done    

    return 0
}

_bl_core_apply_environments() {
    
    [[ $PWD == $HOME* ]] || return
    
    local -a new_environments
    
    _bl_core_resolve_applicable_environments new_environments
    _bl_core_source_in_scope_elements new_environments

    return 0
}

# MARK: Sync
# -----------------------------------------------------------------------------
# @section Environment synchronization

# @description Reconciles the active environments with the current directory by
# unloading exited environments and loading newly entered ones.
#
# @noargs
# @see Used in [hook.md](./hook.sh#cd)
_bl_core_sync() {

    _bl_core_refresh_environments_arrays
    _bl_core_prune_environments
    _bl_core_apply_environments

    return 0
}