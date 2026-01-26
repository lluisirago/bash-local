#!/bin/bash
# -----------------------------------------------------------------------------
# @file core.sh
#
# @brief Internal core API.
# @description Contains all the functions needed to synchronize the bash-local
# environments with the current directory. Not intended to be called directly by
# users.
# -----------------------------------------------------------------------------

# MARK: Envs' files
# -----------------------------------------------------------------------------
# @section Environments' files
# @description Environments' files are used to store the current and previous
# environments between 'cd' executions. They are located in '_BL_STATE[TMP_DIR]'
# and must be refreshed on each execution.
# 
# Note that 'current' and 'previous' describe absolute environment sets
# (i.e. the full environments active at a given directory state) and
# 'old' and 'new' describe relative ones, representing environments to be
# removed from or added to the current state when transitioning between
# directories.
# -----------------------------------------------------------------------------

# @brief Calculates the current environments.
# @description Does it by searching a '.bl' directory in PWD (Path Working
# Directory) parents and storing them in the CURRENT_ENVIRONMENTS_FILE. The
# function does nothing but clear the file if the PWD (Path Working Directory)
# is not inside the HOME directory.
#
# @noargs
# @see _bl_core_refresh_environments_files()
_bl_core_refresh_current_environments_file() {

    : > "${_BL_STATE[CURRENT_ENVIRONMENTS_FILE]}"
    [[ $PWD == "$HOME"* ]] || return

    local dir=$PWD
    while [[ $dir != "$HOME" ]]; do

        if [[ -d "$dir/.bl" ]]; then
            printf '%s\n' "$dir" >> "${_BL_STATE[CURRENT_ENVIRONMENTS_FILE]}"
        fi

        # Remove the last segment of 'dir' (e.g. remove '/segment' from
        # '$HOME/segment')
        dir=${dir%/*}
    done
    return 0
}

# @brief Updates the previous and current environments files.
# @description Sets the current environments as previous by swapping the files'
# variables and calculates the current ones.
#
# @noargs
# @see _bl_core_sync()
_bl_core_refresh_environments_files() {

    # Swap files' variables
    local -r AUX="${_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]}"
    _BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]="${_BL_STATE[CURRENT_ENVIRONMENTS_FILE]}"
    _BL_STATE[CURRENT_ENVIRONMENTS_FILE]="$AUX"
    
    _bl_core_refresh_current_environments_file

    return 0
}

# @brief Gets the previous environments which are not current.
#
# @arg $1 array Reference to the old environments' array.
# @see _bl_core_unload_environments()
_bl_core_get_old_environments() {

    local -n old_environments_=$1

    # Get those in '_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]' not present in
    # '_BL_STATE[CURRENT_ENVIRONMENTS_FILE]'
    mapfile -t old_environments_ < <(
        diff "${_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]}" "${_BL_STATE[CURRENT_ENVIRONMENTS_FILE]}" 2>/dev/null |
        sed -n 's/^< //p'
    )
    return 0
}

# @brief Gets the current environments which are not previous.
#
# @arg $1 array Reference to the new environments' array.
# @see _bl_core_load_environments()
_bl_core_get_new_environments() {

    local -n new_environments_=$1

    # Get those in '_BL_STATE[CURRENT_ENVIRONMENTS_FILE]' not present in
    # '_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]'
    mapfile -t new_environments_ < <(
        diff "${_BL_STATE[CURRENT_ENVIRONMENTS_FILE]}" "${_BL_STATE[PREVIOUS_ENVIRONMENTS_FILE]}" 2>/dev/null |
        sed -n 's/^< //p'
    )
    return 0
}


# MARK: Unload
# -----------------------------------------------------------------------------
# @section Unload stage
# @description Old environments are unloaded at every 'cd' execution (i.e.
# all the elements from each old environment are removed).
# Note that 'unload' refers to an enviroment and 'remove' to an element.
# -----------------------------------------------------------------------------

# @brief Gets all the elements from the old environments, filtered by kind.
# @description A list of these elements is stored at the 'manifest' file located
# inside each environment's '.bl' directory. This function reads the manifests
# in order to get the aliases, functions and variables.
#
# @arg $1 array Constant reference to the old environments' array.
# @arg $2 array Reference to the aliases' array.
# @arg $3 array Reference to the functions' array.
# @arg $4 array Reference to the variables' array.
# @see _bl_core_unload_environments()
_bl_core_collect_elements() {

    local -rn OLD_ENVIRONMENTS=$1
    local -n aliases_=$2
    local -n functions_=$3
    local -n variables_=$4

    for env in "${OLD_ENVIRONMENTS[@]}"; do

        # Extract aliases, functions and variables from '$env/.bl/manifest' file
        # If 'PWD' == 'env' extract local and scoped
        # If 'PWD' != 'env' extract only scoped
        if [[ "$env" == "${_BL_STATE[PPD]}" ]]; then
            local is_env_root=true
        else
            local is_env_root=false
        fi
        
        while IFS= read -r line; do
 
            [[ -z "$line" ]] && continue
            echo "$line"
            if [[ "$line" =~ ${_BL_CONST[SECTION_REGEX]} ]]; then

                local section="${line:1:-1}"
                local scope="${section%%.*}"
                local kind="${section##*.}"
                echo "Section set to $section"

            elif [[ ("$scope" == "${_BL_CONST[SCOPE_LOCAL]}" && "$is_env_root" == true) ||
                     "$scope" == "${_BL_CONST[SCOPE_SCOPED]}" ]]; then
                
                case "$kind" in
                    "${_BL_CONST[KIND_ALIASES]}") aliases_+=("$line") ;;
                    "${_BL_CONST[KIND_FUNCTIONS]}") functions_+=("$line") ;;
                    "${_BL_CONST[KIND_VARIABLES]}") variables_+=("$line") ;;
                esac
                echo "$line added to $kind"
            fi
        done < "$env/.bl/manifest"

        echo "Aliases: ${aliases_[@]}"
        echo "Functions: ${functions_[@]}"
        echo "Variables: ${variables_[@]}"
    done

    unset env line
    return 0
}

# @brief Removes the given elements.
#
# @arg $1 array Constant reference to the aliases' array.
# @arg $2 array Constant reference to the functions' array.
# @arg $3 array Constant reference to the variables' array.
# @see _bl_core_unload_environments()
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

# @brief Unloads the old environments (i.e, those exited at the 'cd' execution).
# @description The function does nothing if the PPD (Path Previous Directory) is
# not inside the HOME directory.
#
# @noargs
# @see _bl_core_sync()
_bl_core_unload_environments() {

    [[ $_BL_STATE[PPD] == $HOME* ]] || return

    local -a old_environments aliases functions variables

    _bl_core_get_old_environments old_environments
    _bl_core_collect_elements old_environments aliases functions variables
    _bl_core_remove_elements aliases functions variables

    return 0
}


# MARK: Load
# -----------------------------------------------------------------------------
# @section Load stage
# @description New environments are loaded at every 'cd' execution (i.e.
# all the elements from each new environment are added).
# Note that 'load' refers to an enviroment and 'add' to an element.
# -----------------------------------------------------------------------------

#ToDo

# MARK: Sync
# -----------------------------------------------------------------------------
# @section Environment synchronization
# -----------------------------------------------------------------------------

# @brief Reconciles the active environments with the current directory by
# unloading exited environments and loading newly entered ones.
#
# @noargs
# @see hook.sh
_bl_core_sync() {

    _bl_core_refresh_environments_files
    _bl_core_unload_environments
    #_bl_core_load_environments

    return 0
}