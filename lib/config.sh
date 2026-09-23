#!/usr/bin/env bash

fail() {
    printf '%s\n' "$*" >&2
    return 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

resolve_configuration_path() {
    local config_path=$1
    local tests_directory=$2
    local base_path=$3
    local files=()
    local selection
    local index=0
    local file

    if [[ -n $config_path ]]; then
        [[ -f $config_path ]] || fail "Missing JSON configuration file: $config_path" || return
        printf '%s\n' "$config_path"
        return
    fi

    [[ -d $tests_directory ]] || fail "Missing tests directory: $tests_directory" || return
    while IFS= read -r file; do
        files[${#files[@]}]=$file
    done < <(find "$tests_directory" -type f -name '*.json' -print | LC_ALL=C sort)

    ((${#files[@]} > 0)) || fail "No JSON configuration files found in tests directory: $tests_directory" || return

    printf 'Select a configuration file:\n' >&2
    for ((index = 0; index < ${#files[@]}; index++)); do
        printf '[%d] %s\n' "$((index + 1))" "${files[index]#"$base_path"/}" >&2
    done

    while :; do
        printf 'Enter a number between 1 and %d: ' "${#files[@]}" >&2
        IFS= read -r selection || return 1
        case $selection in
            ''|*[!0-9]*) ;;
            *)
                if ((selection >= 1 && selection <= ${#files[@]})); then
                    printf '%s\n' "${files[selection - 1]}"
                    return
                fi
                ;;
        esac
    done
}