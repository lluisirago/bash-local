#!/bin/bash
# -----------------------------------------------------------------------------
# @file context.sh
#
# @brief Context definition.
# @description Defines the constants as well as the dynamic state of bash-local.
# -----------------------------------------------------------------------------

# Include Guard
if [[ -z "${_BL_CONST[VERSION]+x}" ]]; then

    declare -grA _BL_CONST=(

        # General information
        [VERSION]="1.1.0"

        # Manifest format
        [SECTION_REGEX]='^\[(.+)\.(.+)\]$'
        [SCOPE_LOCAL]="local"
        [SCOPE_SCOPED]="scoped"
        [KIND_ALIASES]="aliases"
        [KIND_FUNCTIONS]="functions"
        [KIND_VARIABLES]="variables"
    )
fi

declare -gA _BL_STATE=(
    [PPD]=""
    [TMP_DIR]=""
    [PREVIOUS_ENVIRONMENTS_FILE]=""
    [CURRENT_ENVIRONMENTS_FILE]=""
)