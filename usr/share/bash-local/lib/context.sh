#!/bin/bash
# -----------------------------------------------------------------------------
# @file context.sh
#
# @brief Context definition.
# @description Defines the constants as well as the dynamic state of bash-local.

# Include Guard
if [[ -z "${_BL_CONST[VERSION]+x}" ]]; then

    declare -grA _BL_CONST=(

        # General information
        [VERSION]="1.1.0"

        # bl directory
        [BL_DIR]=".bl"

        # Manifest file
        [MANIFEST_FILE]="manifest"
        [SECTION_REGEX]='^\[(.+)\.(.+)\]$'
        [SCOPE_LOCAL]="local"
        [SCOPE_SCOPED]="scoped"
        [KIND_ALIASES]="aliases"
        [KIND_FUNCTIONS]="functions"
        [KIND_VARIABLES]="variables"

        # Source directory
        [SOURCE_DIR]="source"
        [LOCAL_FILE]="local"
        [SCOPED_FILE]="scoped"
    )
fi

declare -gA _BL_STATE=(
    [PPD]=""
)

# Environments state
declare -ga _BL_STATE_PREVIOUS_ENVIRONMENTS=()
declare -ga _BL_STATE_CURRENT_ENVIRONMENTS=()