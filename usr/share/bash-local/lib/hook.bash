#!/bin/bash
# -----------------------------------------------------------------------------
# @file hook.bash
#
# @brief This script implements the `cd` hook.
# @description Change Directory (cd) function is redefined to act as a trigger
# for bash-local synchronization.

# @brief Redefinition of `cd` function
# @see cd --help
cd() {
    
    _BL_STATE[PPD]="$PWD"
    builtin cd "$@" || return
    _bl_core_sync
    
    return 0
}