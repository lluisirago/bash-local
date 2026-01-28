#!/bin/bash
# -----------------------------------------------------------------------------
# @file core.sh
#
# @brief Internal core API.
# @description Contains all the functions needed to synchronize the bash-local
# environments with the current directory. Not intended to be called directly
# by users.
# -----------------------------------------------------------------------------


# MARK: Envs' arrays
# -----------------------------------------------------------------------------
# @section Environments' arrays
# @description Environments' arrays are used to store the current and previous
# environments between `cd` executions. They are located in
# `_BL_STATE_CURRENT_ENVIRONMENTS` and `_BL_STATE_PREVIOUS_ENVIRONMENTS`
# and must be refreshed on each execution.
# Note that *current* and *previous* describe the full environments active at a
# given directory state and *old* and *new* represent environments to be
# removed from or added to the current state when transitioning between
# directories.
# -----------------------------------------------------------------------------

# @description Calculates the current environments.
# Does it by searching a `.bl` directory in PWD (Path Working Directory)
# parents and storing them in `_BL_STATE_CURRENT_ENVIRONMENTS`. The function
# does nothing but clear the array if the PWD (Path Working Directory) is not
# inside the HOME directory.
#
# @noargs
# @see Used in [_bl_core_refresh_environments](#_bl_core_refresh_environments)
_bl_core_refresh_current_environments() {

    _BL_STATE_CURRENT_ENVIRONMENTS=()
    [[ $PWD == "$HOME"* ]] || return

    local dir=$PWD
    while [[ $dir != "$HOME" ]]; do

        # Store if has a `.bl` directory and remove the last segment (e.g. 
        # remove `/segment` from `$HOME/segment`)
        [[ -d "$dir/.bl" ]] && _BL_STATE_CURRENT_ENVIRONMENTS+=("$dir")
        dir=${dir%/*}
    done

    return 0
}

# @description Updates the previous and current environments' arrays.
# Sets the current environments as previous and calculates the current ones.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_refresh_environments() {

    _BL_STATE_PREVIOUS_ENVIRONMENTS=("${_BL_STATE_CURRENT_ENVIRONMENTS[@]}")
    _bl_core_refresh_current_environments

    return 0
}

# @description Gets the previous environments which are not current.
#
# @arg $1 array Reference to the old environments' array.
# @see Used in [_bl_core_unload_environments](#_bl_core_unload_environments)
_bl_core_get_old_environments() {
    
    local -n old_environments_=$1

    local -A current_environments=()
    local environment

    # Load the current environments into the map
    for environment in "${_BL_STATE_CURRENT_ENVIRONMENTS[@]}"; do
        current_environments["$environment"]=1
    done

    # Get the previous environments not in the map
    for environment in "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"; do
        [[ ${current_environments["$environment"]+x} ]] || old_environments_+=("$environment")
    done

    return 0
}

# @description Gets the current environments which are not previous.
#
# @arg $1 array Reference to the new environments' array.
# @see Used in [_bl_core_load_environments](#_bl_core_load_environments)
_bl_core_get_new_environments() {

    local -n new_environments_=$1

    # Get those in `_BL_STATE[CURRENT_ENVIRONMENTS_FILE]` not present in
    # `_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]`
    mapfile -t new_environments_ < <(
        diff "${_BL_STATE[CURRENT_ENVIRONMENTS_FILE]}" "${_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]}" 2>/dev/null |
        sed -n 's/^< //p'
    )
    return 0
}


# MARK: Unload
# -----------------------------------------------------------------------------
# @section Unload stage
# @description Old environments are unloaded at every `cd` execution (i.e.
# all the elements from each old environment are removed).
# Note that *unload* refers to an enviroment and *remove* to an element.
# -----------------------------------------------------------------------------

# @description Gets all the elements from the old environments, filtered by
# kind.
# A list of these elements is stored at the `manifest` file located inside each
# environment's `.bl` directory. This function reads the manifests in order to
# get the aliases, functions and variables.
#
# @arg $1 array Constant reference to the old environments' array.
# @arg $2 array Reference to the aliases' array.
# @arg $3 array Reference to the functions' array.
# @arg $4 array Reference to the variables' array.
# @see Used in [_bl_core_unload_environments](#_bl_core_unload_environments)
_bl_core_collect_elements() {

    local -rn OLD_ENVIRONMENTS=$1
    local -n aliases_=$2
    local -n functions_=$3
    local -n variables_=$4

    local env
    for env in "${OLD_ENVIRONMENTS[@]}"; do

        # Decide if local elements must be removed
        # If `env == PWD` collect local and scoped elements
        # If `env' != 'PWD` collect only scoped elements
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
        done < "$env/.bl/manifest"

        #echo "Aliases: " "${aliases_[@]}"
        #echo "Functions: " "${functions_[@]}"
        #echo "Variables: " "${variables_[@]}"
    done
    return 0
}

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

    for alias in "${ALIASES[@]}"; do
        unalias "$alias" 2>/dev/null
    done

    for function in "${FUNCTIONS[@]}"; do
        unset -f "$function" 2>/dev/null
    done

    for variable in "${VARIABLES[@]}"; do
        unset "$variable" 2>/dev/null
    done

    unset alias function variable
    return 0
}

# @description Unloads the old environments (i.e, those exited at the `cd`
# execution).
# The function does nothing if the PPD (Path Previous Directory) is not inside
# the HOME directory.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_unload_environments() {
    
    [[ ${_BL_STATE[PPD]} == $HOME* ]] || return

    local -a old_environments aliases functions variables
    
    _bl_core_get_old_environments old_environments
    #_bl_core_collect_elements old_environments aliases functions variables
    #_bl_core_remove_elements aliases functions variables

    return 0
}


# MARK: Load
# -----------------------------------------------------------------------------
# @section Load stage
# @description New environments are loaded at every `cd` execution (i.e.
# all the elements from each new environment are added).
# Note that *load* refers to an enviroment and *add* to an element.
# -----------------------------------------------------------------------------

#ToDo


# MARK: Sync
# -----------------------------------------------------------------------------
# @section Environment synchronization
# -----------------------------------------------------------------------------

# @description Reconciles the active environments with the current directory by
# unloading exited environments and loading newly entered ones.
#
# @noargs
# @see Used in [hook.sh](./hook.sh#cd)
_bl_core_sync() {

    _bl_core_refresh_environments
    _bl_core_unload_environments
    #_bl_core_load_environments

    return 0
}