#!/usr/bin/env bash

resolve_environment_file_path() {
    local configuration_path=$1
    local current_directory

    current_directory=$(cd "$(dirname "$configuration_path")" && pwd -P) || return
    while [[ $current_directory != / ]]; do
        if [[ -f $current_directory/.env ]]; then
            printf '%s\n' "$current_directory/.env"
            return
        fi
        current_directory=$(dirname "$current_directory")
    done

    [[ -f /.env ]] && printf '%s\n' '/.env'
}

import_environment_file() {
    local path=$1
    local line
    local name
    local value

    [[ -z $path ]] && return
    [[ -f $path ]] || fail "Missing environment file: $path" || return

    while IFS= read -r line || [[ -n $line ]]; do
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z $line || ${line#\#} != "$line" ]] && continue
        [[ $line == *=* ]] || fail "Invalid line in $path: $line" || return
        name=${line%%=*}
        value=${line#*=}
        name=$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -n $name ]] || fail "Invalid line in $path: $line" || return
        if [[ ${value:0:1} == '"' && ${value: -1} == '"' ]] || [[ ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
            value=${value:1:${#value}-2}
        fi
        export "$name=$value"
    done < "$path"
}

assert_required_environment_variables() {
    local variable_name
    for variable_name in "$@"; do
        [[ -n ${!variable_name:-} ]] || fail "Missing required environment variable: $variable_name" || return
    done
}