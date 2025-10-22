# ~/.bash/bash-local/main.bash
# -----------------------------------------------------------------------------
# This script implements bash-local.
#
# bash-local provides a way to maintain a unique environment
# (aliases, functions, and variables) for each directory.
# It coexists with the usual Bash environment.
# -----------------------------------------------------------------------------

# Notes:
# (1) Both environment files will have writing permissions disabled. The
#     modification of these files, following a change in permissions, could
#     lead to unwanted behavior. However, it is fixed by restarting the
#     terminal.
#
# (2) Unlike modifications, deleting or moving environment files are
#     contemplated scenarios.

# Stores the current environment in the given file.
# @param ENV_FILE The path of the file.
storeEnv() {

    local -r ENV_FILE=$1
    
    if [[ -f "$ENV_FILE" ]]; then
        chmod +w "$ENV_FILE"
    else
        touch "$ENV_FILE"
    fi
	{ alias -p; declare -F; compgen -v; } > "$ENV_FILE"
	chmod -w "$ENV_FILE"
}

# Initializes the environment files (bash-env and bash-local-env).
# @param BASH_ENV Path to the bash-env file.
# @param BASH_LOCAL_ENV Path to the bash-local-env file.
setEnvFiles() {
	
	local -r BASH_ENV=$1
	local -r BASH_LOCAL_ENV=$2
	
    storeEnv "$BASH_ENV"
	
	[[ ! -f "$BASH_LOCAL_ENV" ]] && touch "$BASH_LOCAL_ENV"
	chmod -w "$BASH_LOCAL_ENV"
}

# Gets the aliases, functions, and variables from the current environment.
# @param aliases_ Reference to the aliases' array.
# @param functions_ Reference to the functions' array.
# @param variables_ Reference to the variables' array.
getCurrentEnv() {

    local -n aliases_=$1
    local -n functions_=$2
    local -n variables_=$3
    
    local -a lines
    
    # Get the environment as an array.
    mapfile -t lines < <(alias -p; declare -F; compgen -v)
    
    for line in "${lines[@]}"; do
        case "$line" in
            alias*)
                # Get between 'alias ' and '=' 
                name="${line#alias }"
                name="${name%%=*}"
                aliases_+=("$name")
                ;;
            declare\ -f*)
                # Get after 'declare -f '
                name="${line#declare -f }"
                functions_+=("$name")
                ;;
            *)         
                # Get all       
                variables_+=("$name")
                ;;
        esac
    done
    
    unset line name
}

# Gets the aliases, functions, and variables from the bash-local-env file.
# @param BASH_ENV Path to the bash-env file.
# @param BASH_LOCAL_ENV Path to the bash-local-env file.
# @param aliases_ Reference to the aliases' array.
# @param functions_ Reference to the functions' array.
# @param variables_ Reference to the variables' array.
# @pre Both environment files are up-to-date.
getLocalEnv() {
    
    local -r BASH_ENV=$1
    local -r BASH_LOCAL_ENV=$2
    local -n aliases_=$3
    local -n functions_=$4
    local -n variables_=$5
    
	local -a added
    
    # Get the lines in BASH_LOCAL_ENV that don't exist in BASH_ENV.
    # The added array will contain the differences (additions) to the environment.
    mapfile -t added < <(diff "$BASH_ENV" "$BASH_LOCAL_ENV" 2>/dev/null | grep '^> ')
    
    for line in "${added[@]}"; do
        line="${line#> }"
        case "$line" in
            alias*)
                # Get between 'alias ' and '=' 
                name="${line#alias }"
                name="${name%%=*}"
                aliases_+=("$name")
                ;;
            declare\ -f*)
                # Get after 'declare -f '
                name="${line#declare -f }"
                functions_+=("$name")
                ;;
            *)         
                # Get all       
                variables_+=("$name")
                ;;
        esac
    done
    
    unset line name
}

# Removes the aliases, functions, and variables given from the current
# environment.
# @param ALIASES Constant reference to the aliases' array.
# @param FUNCTIONS Constant reference to the functions' array.
# @param VARIABLES Constant reference to the variables' array.
# @pre The environment to unsource is a valid one, got from a getEnv function.
unsourceEnv() {
    
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
}

# Removes the whole environment and loads the global environment (as if the
# terminal was restarted).
# This is very inefficient and should only be used if bash-env file is invalid
# or inaccessible; in any other case, use restoreEnv instead.
# @param BASH_ENV Path to the bash-env file.
resetEnv() {

    local -r BASH_ENV=$1
    
    local -a aliases functions variables
	
    getCurrentEnv aliases functions variables
	unsourceEnv aliases functions variables
	
    source $HOME/.bashrc
	storeEnv "$BASH_ENV"
}

# Removes the local environment (restores the global one)
# @param BASH_ENV Path to the bash-env file.
# @param BASH_LOCAL_ENV Path to the bash-local-env file.
restoreEnv() {

    local -r BASH_ENV=$1
    local -r BASH_LOCAL_ENV=$2
    
	local -a aliases functions variables
    getLocalEnv "$BASH_ENV" "$BASH_LOCAL_ENV" aliases functions variables
	unsourceEnv aliases functions variables
}

# Loads the local environment and stores it in the bash-local-env file.
# @param BASH_LOCAL_ENV Path to the bash-local-env file.
# @pre .bash-local directory exists.
loadLocalEnv() {
    
    local -r BASH_LOCAL_ENV=$1
    
	local -r BASH_LOCAL_EXT=".bash-local"
	local -r BASH_LOCAL_DIR="$PWD/$BASH_LOCAL_EXT"
	
	# Load all .bash-local files from BASH_LOCAL_DIR
	shopt -s globstar
	for file in "$BASH_LOCAL_DIR"/**/*"$BASH_LOCAL_EXT"; do
	    if [[ -r "$file" ]]; then
	        source "$file"
	    fi
	done
	
	storeEnv "$BASH_LOCAL_ENV"
    
    unset file
}

# Override of the cd function.
# Checks if the origin directory is a local environment, if so restores the
# global one. Then, checks if the destination directory is a local
# environment, if so loads it.
cd() {
    
    local -r PREVIOUS_DIR="$PWD" 
    
    builtin cd "$@" || return
	
	local -r BASH_ENV="$HOME/.bash/bash-local/bash-env"
    local -r BASH_LOCAL_ENV="$HOME/.bash/bash-local/bash-local-env"
	
	# Restore stage
    if [[ -d "$PREVIOUS_DIR/.bash-local" ]]; then
        
        [[ -f "$BASH_ENV" ]] || resetEnv "$BASH_ENV"
        [[ -f "$BASH_LOCAL_ENV" ]] || storeEnv "$BASH_LOCAL_ENV"
        
        restoreEnv "$BASH_ENV" "$BASH_LOCAL_ENV"
        
    elif [[ ! -f "$BASH_ENV" || ! -f "$BASH_LOCAL_ENV" ]]; then
    
        setEnvFiles "$BASH_ENV" "$BASH_LOCAL_ENV"
    fi
    
    # Load stage
    [[ -d ".bash-local" ]] && loadLocalEnv "$BASH_LOCAL_ENV"
}
