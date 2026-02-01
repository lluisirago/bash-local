#!/bin/bash
# -----------------------------------------------------------------------------
# @file hook.bash
#
# @brief Implements `cd` hook.
# @description Change Directory (`cd`) function is redefined to act as trigger
# for bash-local synchronization.

# @description Redefinition of `cd` function. Same arguments as default `cd`.
cd() {
    
    _BL_STATE[PPD]="$PWD"
    builtin cd "$@" || return
    _bl_core_sync
    return 0
}