#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file core.bash
#
# @brief Internal core API for bash-local.
#
# @description
# This module implements the core synchronization logic between the shell
# environment and the current working directory.
#
# It tracks environment transitions while navigating the filesystem and
# reconciles shell state accordingly by:
# - Pruning elements from exited environments.
# - Applying elements from newly entered environments.
#
# The module is not intended to be called directly by users.
#
# ---
#
# Environment transition model:
#
# | From \ To | Outside | Child | Root |
# |-----------|---------|-------|------|
# | Outside   |   -     | Source scoped | Source scoped and local |
# | Child     | Remove scoped |   -   | Source local |
# | Root      | Remove scoped and local | Remove local |   -   |
#
# ---
#
# Global state used by this module:
#
# - `BL_STATE_CURRENT_ENVIRONMENTS`:
#     List of environments active for the current PWD.
#
# - `_BL_STATE_PREVIOUS_ENVIRONMENTS`:
#     List of environments active for the previous PWD.
#
# - `_BL_STATE[PPD]`:
#     Previous working directory.


# MARK: Envs' state
# -----------------------------------------------------------------------------
# @section Environment state tracking
#
# Functions in this section maintain the current and previous environment sets
# derived from the working directory.

# @description Computes the set of active environments for the current `PWD`.
#
# An environment is considered active if a `bl/` directory exists in the path
# hierarchy between `PWD` and `HOME`.
#
# The function does nothing but clear current environments state if `PWD` is not
# inside `HOME` directory.
#
# Side effects:
# - Writes: `_BL_STATE_CURRENT_ENVIRONMENTS`
#
# @noargs
# @see Used in [_bl_core_refresh_environments_state]
# (#_bl_core_refresh_environments_state)
_bl_core_refresh_current_environments_state() {

    _BL_STATE_CURRENT_ENVIRONMENTS=()
    [[ $PWD == "$HOME"* ]] || return

    local dir=$PWD
    while [[ $dir != "$HOME" ]]; do

        # Store if has a `bl` directory and remove the last segment (e.g. 
        # remove `/segment` from `$HOME/segment`)
        if [[ -d "$dir/${_BL_CONST[BL_DIR]}" ]]; then
            _BL_STATE_CURRENT_ENVIRONMENTS+=("$dir")
        fi
        dir=${dir%/*}
    done
}

# @description Updates the environment state by shifting the current
# environments to the previous set and recomputing the current ones.
#
# This function must be called once per directory change before any pruning or
# applying logic is executed.
#
# Side effects:
# - Reads: `_BL_STATE_CURRENT_ENVIRONMENTS`
# - Writes: `_BL_STATE_PREVIOUS_ENVIRONMENTS`
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_refresh_environments_state() {

    _BL_STATE_PREVIOUS_ENVIRONMENTS=("${_BL_STATE_CURRENT_ENVIRONMENTS[@]}")
    _bl_core_refresh_current_environments_state
}


# MARK: Manifest
# -----------------------------------------------------------------------------
# @section Prune stage
#
# Functions in this section are the responsible for accessing the manifest
# files. They collect, remove and add rows from/to the file.

# @description Collects elements' name from an environment manifest.
#
# Depending on the provided flags, local and/or scoped elements are extracted
# from the environment's manifest file and appended to the given
# arrays.
#
# If neither local nor scoped elements are requested, the function is a no-op.
#
# @arg $1 string Environment path.
# @arg $2 bool   Whether to collect local elements.
# @arg $3 bool   Whether to collect scoped elements.
# @arg $4 array  Reference to aliases array.
# @arg $5 array  Reference to functions array.
# @arg $6 array  Reference to variables array.
#
# @see Used in [_bl_core_resolve_prunable_elements]
# (#_bl_core_resolve_prunable_elements)
_bl_core_collect_from_manifest_by_scope() {

    local -r ENVIRONMENT="$1"
    local -r COLLECT_LOCAL_ELEMENTS="$2"
    local -r COLLECT_SCOPED_ELEMENTS="$3"
    local -n aliases__=$4
    local -n functions__=$5
    local -n variables__=$6
    
    [[ "$COLLECT_LOCAL_ELEMENTS" == true ||
       "$COLLECT_SCOPED_ELEMENTS" == true ]] || return

    # Map manifest into LINES array
    local LINES=()
    mapfile -t LINES < \
        "$ENVIRONMENT/${_BL_CONST[BL_DIR]}/${_BL_CONST[MANIFEST_FILE]}"

    local -r SCOPED_OFFSET="${LINES[0]}"

    # Decide the lines to read
    local INITIAL_LINE=1
    local END_LINE="${#LINES[@]}"
    [[ "$COLLECT_LOCAL_ELEMENTS" == false ]] && INITIAL_LINE="$SCOPED_OFFSET"
    [[ "$COLLECT_SCOPED_ELEMENTS" == false ]] && END_LINE="$SCOPED_OFFSET"

    for (( _i_ = INITIAL_LINE; _i_ < END_LINE; _i_++ )); do

        read -r name scope kind first last <<< "${LINES[i]}"

        case "$kind" in
            "${_BL_CONST[KIND_ALIAS]}") aliases__+=("$name");;
            "${_BL_CONST[KIND_FUNCTION]}") functions__+=("$name");;
            "${_BL_CONST[KIND_VARIABLE]}") variables__+=("$name");;
        esac
    done
}

# @description Collects elements' scope, first and last line at the source file
# from an environment manifest.
#
# Depending on the provided names, elements are extracted from the environment's
# manifest file and appended to the given arrays.
#
# Element traits collected will be at the same position as the element name in
# the given names array.
#
# If no elements are requested, the function is a no-op.
#
# @arg $1 string Environment path.
# @arg $2 array  Constant reference to names array.
# @arg $3 array  Reference to scopes array.
# @arg $3 array  Reference to first lines array.
# @arg $4 array  Reference to last lines array.
#
# @see Used in 
_bl_core_collect_from_manifest_by_name() {
    
    local -r ENVIRONMENT="$1"
    local -rn NAMES=$2
    local -n scopes_=$3
    local -n firsts_=$4
    local -n lasts_=$5

    [[ "${#NAMES[@]}" -ne 0 ]] || return

    # Map manifest into LINES array
    local LINES=()
    mapfile -t LINES < \
        "$ENVIRONMENT/${_BL_CONST[BL_DIR]}/${_BL_CONST[MANIFEST_FILE]}"
    
    for (( _i_ = 1; _i_ < "${#LINES[@]}"; _i_++ )); do

        read -r name scope kind first last <<< "${LINES[i]}"

        for (( _j_ = 0; _j_ < "${#NAMES[@]}"; _j_++ )); do

            if [[ "$name" == "${LINES["$_i_"]}" ]]; then
                scopes_[_j_]="$scope"
                firsts_[_j_]="$first"
                lasts_[_j_]="$last"
            fi
        done
    done
}


# MARK: Prune
# -----------------------------------------------------------------------------
# @section Prune stage
#
# Functions in this section determine which shell elements must be removed when
# environments are exited as a result of directory transitions.

# @description Determines which shell elements must be removed based on
# environment transitions.
#
# Elements are selected according to transitions between the previous and
# current environment sets (Outside / Child / Root).
#
# Only environments that are no longer active or have changed role are
# considered prunable.
#
# @arg $1 array Reference to aliases array.
# @arg $2 array Reference to functions array.
# @arg $3 array Reference to variables array.
#
# @see Used in [_bl_core_prune_environments](#_bl_core_prune_environments)
_bl_core_resolve_prunable_elements() {
    
    local -n aliases_=$1
    local -n functions_=$2
    local -n variables_=$3

    local -A current_environments=()
    local environment

    # Load current environments into map
    for environment in "${_BL_STATE_CURRENT_ENVIRONMENTS[@]}"; do
        current_environments["$environment"]=1
    done

    # Iterate through previous environments 
    for environment in "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"; do

        local collect_local_elements=false
        local collect_scoped_elements=false

        # Root to child
        # Still active (current and previous) and is previous root but not
        # current
        if [[ ${current_environments["$environment"]+x} &&
              "$environment" == "${_BL_STATE[PPD]}" &&
              "$environment" != "$PWD" ]]; then

            collect_local_elements=true

        # Child to outside
        # Not active anymore and is not previous root
        elif [[ ! ${current_environments["$environment"]+x} &&
                "$environment" != "${_BL_STATE[PPD]}" ]]; then

            collect_scoped_elements=true

        # Root to outside
        # Not active anymore and is previous root
        elif [[ ! ${current_environments["$environment"]+x} &&
                "$environment" == "${_BL_STATE[PPD]}" ]]; then

            collect_local_elements=true
            collect_scoped_elements=true
        fi
        _bl_core_collect_from_manifest_by_scope "$environment" \
        "$collect_local_elements" "$collect_scoped_elements" \
        aliases_ functions_ variables_
    done
}

# @description Removes shell elements from the current shell session.
#
# Aliases, functions, and variables are disabled silently if they exist.
# Missing elements are ignored.
#
# Side effects:
# - Modifies shell state.
#
# @arg $1 array Constant reference to aliases array.
# @arg $2 array Constant reference to functions array.
# @arg $3 array Constant reference to variables array.
#
# @see Used in [_bl_core_prune_environments](#_bl_core_prune_environments)
_bl_core_disable_elements() {

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
}

# @description Prunes exited environments by disabling their shell elements.
#
# The function determines prunable environments based on the previous and
# current environment state and disables their scoped and/or local elements
# accordingly.
#
# If the previous directory (`PPD`) is outside `$HOME`, the function is a no-op.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_prune_environments() {
    
    [[ ${_BL_STATE[PPD]} == $HOME* ]] || return

    local -a aliases functions variables
    _bl_core_resolve_prunable_elements aliases functions variables
    _bl_core_disable_elements aliases functions variables
}


# MARK: Apply
# -----------------------------------------------------------------------------
# @section Apply stage
#
# Functions in this section determine which environment files must be sourced
# when entering new environments.

# @description Collects source files from an environment.
#
# Depending on the provided flags, local and/or scoped source files are appended
# to the given files array.
#
# @arg $1 string Environment path.
# @arg $2 bool   Whether to collect the local source file.
# @arg $3 bool   Whether to collect the scoped source file.
# @arg $4 array  Reference to files array.
#
# @see Used in [_bl_core_resolve_applicable_environments]
# (#_bl_core_resolve_applicable_environments)
_bl_core_collect_files() {

    local -r ENVIRONMENT="$1"
    local -r COLLECT_LOCAL_FILE="$2"
    local -r COLLECT_SCOPED_FILE="$3"
    local -n files__=$4

    local -r BL_PATH="$ENVIRONMENT/${_BL_CONST[BL_DIR]}/"

    if [[ "$COLLECT_LOCAL_FILE" == true ]]; then
        files__+=("$BL_PATH/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[LOCAL_FILE]}")
    fi

    if [[ "$COLLECT_SCOPED_FILE" == true ]]; then
        files__+=("$BL_PATH/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[SCOPED_FILE]}")
    fi
}

# @description Determines which environment files must be sourced based on
# environment transitions.
#
# Files are selected according to transitions between the previous and current
# environment sets (Outside / Child / Root).
#
# @arg $1 array Reference to files array.
#
# @see Used in [_bl_core_apply_environments](#_bl_core_apply_environments)
_bl_core_resolve_applicable_environments() {

    local -n files_=$1

    local -A previous_environments=()
    local environment

    # Load the previous environments into the map
    for environment in "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"; do
        previous_environments["$environment"]=1
    done

    # Iterate through applicable environments
    for environment in "${_BL_STATE_CURRENT_ENVIRONMENTS[@]}"; do

        local collect_local_file=false
        local collect_scoped_file=false

        # Child to root
        # Still active (previous and current) and is current root but not
        # previous
        if [[ ${previous_environments["$environment"]+x} &&
              "$environment" == "$PWD" &&
              "$environment" != "${_BL_STATE[PPD]}" ]]; then

            collect_local_file=true

        # Outside to child
        # Becomes active and is not current root
        elif [[ ! ${previous_environments["$environment"]+x} &&
                "$environment" != "$PWD" ]]; then

            collect_scoped_file=true

        # Outside to root
        # Becomes active and is current root
        elif [[ ! ${previous_environments["$environment"]+x} &&
                "$environment" == "$PWD" ]]; then

            collect_local_file=true
            collect_scoped_file=true
        fi
        _bl_core_collect_files "$environment" "$collect_local_file" \
        "$collect_scoped_file" files_
    done
}

# @description Sources environment files into the current shell session.
#
# Files are sourced in the order they appear in the provided array.
#
# Side effects:
# - Executes shell code.
#
# @arg $1 array Constant reference to files array.
#
# @see Used in [_bl_core_apply_environments](#_bl_core_apply_environments)
_bl_core_source_files() {

    local -rn FILES=$1

    local file
    for file in "${FILES[@]}"; do
        source "$file"
    done
}

# @description Applies newly entered environments by sourcing their files.
#
# The function determines applicable environments based on the current
# environment state and sources their scoped and/or local files accordingly.
#
# If `PWD` is outside `$HOME`, the function is a no-op.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_apply_environments() {
    
    [[ $PWD == $HOME* ]] || return
    
    local -a files
    _bl_core_resolve_applicable_environments files
    _bl_core_source_files files
}

# MARK: Sync
# -----------------------------------------------------------------------------
# @section Environment synchronization
#
# High-level synchronization entry point combining state refresh, pruning, and
# application stages.

# @description Synchronizes shell state with the current working directory.
#
# This function:
# 1. Refreshes environment state.
# 2. Prunes exited environments.
# 3. Applies newly entered environments.
#
# It is intended to be invoked from the directory change hook.
#
# @noargs
# @see Used in [hook.bash](./hook.md#cd)
_bl_core_sync() {

    _bl_core_refresh_environments_state
    _bl_core_prune_environments
    _bl_core_apply_environments
}