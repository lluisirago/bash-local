#!/user/bin/env bash
# -----------------------------------------------------------------------------
# @file file.bash
#
# @brief Files manager.

# Include Guard
[[ -n "${_BL_FILE_LOADED:-}" ]] && return 0
declare -gr _BL_FILE_LOADED=1

# MARK: Public
# -----------------------------------------------------------------------------
# @section Public funtions
#
# Functions in this section are intended to be called by other modules.

# @description Reads the file lines, mapping them into given array.
#
# @arg $1 string File.
# @arg $2 array Reference to lines array.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
bl_file_read_lines() {

    local -r FILE="$1"
    local -n lines=$2

    if ! mapfile -t lines < "$FILE"; then
        bl_log_debug "FATAL_READ" "$FILE"
        return 1
    fi
}

# @description Writes atomically into a file. If source is an array, each
# element will be treated as a line.
#
# @arg $1 string Absolute path to file.
# @arg $2 array Constant reference to source.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
bl_file_write_atomic() {

    local -r FILE="$1"
    local -rn SOURCE=$2
    local -r DIR=${FILE%/*}
    
    local tmp
    bl_file_create_tmp "$DIR" tmp || return
    
    # shellcheck disable=SC2329
    cleanup_return() {
        local status=$?
        rm -f -- "$tmp"
        trap - RETURN
        [[ -n ${old_trap_:-} ]] && eval "$old_trap_"
        return "$status"
    }
    
    local old_trap_
    old_trap_=$(trap -p RETURN)
    trap cleanup_return RETURN

    bl_file_write "$tmp" SOURCE || return
    bl_run_external mv -f -- "$tmp" "$FILE" || return
}

# @description Creates a temporary file inside the given directory.
#
# @arg $1 string Directory.
# @arg $2 array Reference to temporary file path.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
bl_file_create_tmp() {

    local -r DIR="$1"
    local -n tmp__=$2

    if ! tmp__="$(mktemp "$DIR/.tmp.XXXXXX")"; then
        bl_log_debug "FATAL_CREATE_TMP" "$DIR"
        tmp__=""
        return 1
    fi
}

# @description Writes into a file. If source is an array, each element will be
# treated as a line.
#
# @arg $1 string File.
# @arg $2 array Constant reference to source.
#
# @exitcode 0 Success.
# @exitcode 1 Internal error (logged in debug).
bl_file_write() {

    local -r FILE="$1"
    local -rn SOURCE_=$2
    
    if [[ $(declare -p "${!SOURCE_}" 2>/dev/null) =~ ^declare\ -[^[:space:]]*[aA] ]]; then
        
        [[ ${#SOURCE_[@]} -eq 0 ]] && return 0

        if ! printf '%s\n' "${SOURCE_[@]}" > "$FILE"; then
            bl_log_debug "FATAL_WRITE" "$FILE"
            return 1
        fi
    else

        [[ -z "$SOURCE_" ]] && return 0

        if ! printf '%s\n' "$SOURCE_" > "$FILE"; then
            bl_log_debug "FATAL_WRITE" "$FILE"
            return 1
        fi
    fi
}


# MARK: Modules
# -----------------------------------------------------------------------------
# @section Source modules
source "$(dirname "${BASH_SOURCE[0]}")/config.bash"
source "$(dirname "${BASH_SOURCE[0]}")/manifest.bash"
source "$(dirname "${BASH_SOURCE[0]}")/source.bash"

