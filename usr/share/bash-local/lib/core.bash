#!/bin/bash
# -----------------------------------------------------------------------------
# @file core.bash
#
# @brief Internal core API.
# @description Contains all functions needed to synchronize bash-local
# environments with current directory. Not intended to be called directly
# by users.
#
# Actions on each environment according to state:
# | From \ To | Outside | Child | Root |
# | - | - | - | - |
# | **Outside** | - | Source scoped | Source scoped and local |
# | **Child** | Remove scoped | - | Source local |
# | **Root** | Remove scoped and local | Remove local | - |


# MARK: Envs' state
# -----------------------------------------------------------------------------
# @section Environments' state

# @description Calculates current environments by storing `PWD` parents with
# `bl` directory.
#
# The function does nothing but clear current environments state if `PWD` is not
# inside `HOME` directory.
#
# @noargs
# @see Used in [_bl_core_refresh_environments_state](#_bl_core_refresh_environments_state)
_bl_core_refresh_current_environments_state() {

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

# @description Updates previous and current environments (i.e. sets current
# environments as previous and calculates current ones).
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_refresh_environments_state() {

    _BL_STATE_PREVIOUS_ENVIRONMENTS=("${_BL_STATE_CURRENT_ENVIRONMENTS[@]}")
    _bl_core_refresh_current_environments_state
    return 0
}


# MARK: Prune
# -----------------------------------------------------------------------------
# @section Prune stage

# @description Gets elements (local or scoped) from environment.
#
# @arg $1 string Environment.
# @arg $2 bool Collect local elements.
# @arg $3 bool Collect scoped elements.
# @arg $4 array Reference to aliases' array.
# @arg $5 array Reference to functions' array.
# @arg $6 array Reference to variables' array.
# @see Used in [_bl_core_resolve_prunable_elements](#_bl_core_resolve_prunable_elements)
_bl_core_collect_elements() {

    local -r ENVIRONMENT="$1"
    local -r COLLECT_LOCAL_ELEMENTS="$2"
    local -r COLLECT_SCOPED_ELEMENTS="$3"
    local -n aliases__=$4
    local -n functions__=$5
    local -n variables__=$6
    
    [[ "$COLLECT_LOCAL_ELEMENTS" == true ||
       "$COLLECT_SCOPED_ELEMENTS" == true ]] || return

    # Read manifest
    local line
    while IFS= read -r line; do

        [[ -z "$line" ]] && continue
        
        # `line` is a section header (e.g. [local.aliases])
        if [[ "$line" =~ ${_BL_CONST[SECTION_REGEX]} ]]; then

            local section="${line:1:-1}"
            local scope="${section%%.*}"
            local kind="${section##*.}"

        # `line` is an element
        elif [[ ("$scope" == "${_BL_CONST[SCOPE_LOCAL]}" && "$COLLECT_LOCAL_ELEMENTS" == true) ||
                ("$scope" == "${_BL_CONST[SCOPE_SCOPED]}" && "$COLLECT_SCOPED_ELEMENTS" == true) ]]; then
            
            case "$kind" in
                "${_BL_CONST[KIND_ALIASES]}") aliases__+=("$line") ;;
                "${_BL_CONST[KIND_FUNCTIONS]}") functions__+=("$line") ;;
                "${_BL_CONST[KIND_VARIABLES]}") variables__+=("$line") ;;
            esac
        fi
    done < "$ENVIRONMENT/${_BL_CONST[BL_DIR]}/${_BL_CONST[MANIFEST_FILE]}"
    return 0
}

# @description Gets elements to remove. Only prunable environments will be
# affected.
#
# Elements to remove based on prunable environment:
# - **Root** to **child**: local elements.
# - **Child** to **outside**: scoped elements.
# - **Root** to **outside**: local and scoped elements.
#
# @arg $1 array Reference to aliases' array.
# @arg $2 array Reference to functions' array.
# @arg $3 array Reference to variables' array.
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

    # Iterate through prunable environments 
    for environment in "${_BL_STATE_PREVIOUS_ENVIRONMENTS[@]}"; do

        local collect_local_elements=false
        local collect_scoped_elements=false

        # Root to child
        # Still active (current and previous) and is previous root but not current
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
        _bl_core_collect_elements "$environment" "$collect_local_elements" \
        "$collect_scoped_elements" aliases_ functions_ variables_
    done
    return 0
}

# @description Removes elements.
#
# @arg $1 array Constant reference to aliases' array.
# @arg $2 array Constant reference to functions' array.
# @arg $3 array Constant reference to variables' array.
# @see Used in [_bl_core_prune_environments](#_bl_core_prune_environments)
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

# @description Prunes environments based on element scope.
#
# The function does nothing if `PPD` (Path Previous Directory) is not inside
# `HOME` directory.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_prune_environments() {
    
    [[ ${_BL_STATE[PPD]} == $HOME* ]] || return

    local -a aliases functions variables
    _bl_core_resolve_prunable_elements aliases functions variables
    _bl_core_remove_elements aliases functions variables
    return 0
}


# MARK: Apply
# -----------------------------------------------------------------------------
# @section Apply stage

# @description Gets file (local or scoped) from environment.
#
# @arg $1 string Environment.
# @arg $2 bool Collect local file.
# @arg $3 bool Collect scoped file.
# @arg $4 array Reference to files' array.
# @see Used in [_bl_core_resolve_applicable_environments](#_bl_core_resolve_applicable_environments)
_bl_core_collect_files() {

    local -r ENVIRONMENT="$1"
    local -r COLLECT_LOCAL_FILE="$2"
    local -r COLLECT_SCOPED_FILE="$3"
    local -n files__=$4

    if [[ "$COLLECT_LOCAL_FILE" == true ]]; then
        files__+=("$ENVIRONMENT/${_BL_CONST[BL_DIR]}/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[LOCAL_FILE]}")
    fi

    if [[ "$COLLECT_SCOPED_FILE" == true ]]; then
        files__+=("$ENVIRONMENT/${_BL_CONST[BL_DIR]}/${_BL_CONST[SOURCE_DIR]}/${_BL_CONST[SCOPED_FILE]}")
    fi
    return 0
}

# @description Gets the files to source. Only applicable environments will be
# affected.
#
# File to source based on applicable environment:
# - **Child** to **root**: local file.
# - **Outside** to **child**: scoped file.
# - **Outside** to **root**: local and scoped files.
#
# @arg $1 array Reference to files' array.
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
        # Still active (previous and current) and is current root but not previous
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
    return 0
}

# @description Sources files.
#
# @arg $1 array Constant reference to files' array.
# @see Used in [_bl_core_apply_environments](#_bl_core_apply_environments)
_bl_core_source_files() {

    local -rn FILES=$1

    local file
    for file in "${FILES[@]}"; do
        source "$file"
    done
    return 0
}

# @description Applies environments based on element scope.
#
# The function does nothing if `PWD` is not inside `HOME` directory.
#
# @noargs
# @see Used in [_bl_core_sync](#_bl_core_sync)
_bl_core_apply_environments() {
    
    [[ $PWD == $HOME* ]] || return
    
    local -a files
    _bl_core_resolve_applicable_environments files
    _bl_core_source_files files
    return 0
}

# MARK: Sync
# -----------------------------------------------------------------------------
# @section Environment synchronization

# @description Reconciles active environments with current directory by
# pruning exited environments and applying newly entered ones.
#
# @noargs
# @see Used in [hook.md](./hook.sh#cd)
_bl_core_sync() {

    _bl_core_refresh_environments_state
    _bl_core_prune_environments
    _bl_core_apply_environments
    return 0
}