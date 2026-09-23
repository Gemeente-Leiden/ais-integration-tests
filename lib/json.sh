#!/usr/bin/env bash

import_json_file() {
    local path=$1

    [[ -f $path ]] || fail "Missing JSON configuration file: $path" || return
    jq -e 'type == "object"' "$path" >/dev/null 2>&1 || fail "Invalid JSON configuration file: $path" || return
    JSON_CONFIGURATION_PATH=$path
}

json_required_value() {
    local path=$1
    jq -er --arg path "$path" '
        getpath($path | split(".")) // error("missing")
    ' "$JSON_CONFIGURATION_PATH" 2>/dev/null || fail "Missing required JSON setting: $path"
}

json_required_string() {
    local path=$1
    jq -er --arg path "$path" '
        getpath($path | split(".")) | select(type == "string" and length > 0)
    ' "$JSON_CONFIGURATION_PATH" 2>/dev/null || fail "JSON setting must be a non-empty string: $path"
}

json_positive_integer() {
    local path=$1
    jq -er --arg path "$path" '
        getpath($path | split(".")) | select(type == "number" and floor == . and . > 0)
    ' "$JSON_CONFIGURATION_PATH" 2>/dev/null || fail "JSON setting must be a positive integer: $path"
}

json_integer_list() {
    local path=$1
    local minimum=$2
    local maximum=$3
    jq -er --arg path "$path" --argjson minimum "$minimum" --argjson maximum "$maximum" '
        getpath($path | split(".")) |
        select(type == "array" and length > 0 and all(
            .[];
            type == "number" and floor == . and . >= $minimum and . <= $maximum
        )) |
        .[]
    ' "$JSON_CONFIGURATION_PATH" 2>/dev/null || fail "JSON setting values must be integers between $minimum and $maximum: $path"
}

resolve_json_placeholders() {
    jq -ce '
        def replace_placeholders:
            gsub("\\$\\{(?<name>[A-Za-z_][A-Za-z0-9_]*)\\}";
                .name as $name |
                env[$name] as $value |
                if $value == null or $value == "" then
                    error("No value found for JSON placeholder: ${" + $name + "}")
                else $value end);
        walk(if type == "string" then replace_placeholders else . end)
    ' 2>&1
}

get_json_request_configuration() {
    local request_json

    json_required_string 'request.endpoint' >/dev/null || return
    json_required_string 'request.method' >/dev/null || return
    jq -e '.request.headers | type == "object"' "$JSON_CONFIGURATION_PATH" >/dev/null 2>&1 || {
        fail 'JSON setting must be an object: request.headers'
        return
    }

    request_json=$(jq -c '{endpoint: .request.endpoint, method: .request.method, headers: .request.headers, body: (if .request | has("body") then .request.body else null end)}' "$JSON_CONFIGURATION_PATH" | resolve_json_placeholders) || return
    REQUEST_ENDPOINT=$(printf '%s' "$request_json" | jq -r '.endpoint')
    REQUEST_METHOD=$(printf '%s' "$request_json" | jq -r '.method')
    REQUEST_HEADERS_JSON=$(printf '%s' "$request_json" | jq -c '.headers')
    REQUEST_HAS_BODY=$(printf '%s' "$request_json" | jq -r '.body != null')
    if [[ $REQUEST_HAS_BODY == true ]]; then
        if [[ $(printf '%s' "$request_json" | jq -r '.body | type') == string ]]; then
            REQUEST_BODY=$(printf '%s' "$request_json" | jq -r '.body')
        else
            REQUEST_BODY=$(printf '%s' "$request_json" | jq -c '.body')
        fi
    else
        REQUEST_BODY=''
    fi
}

get_tcp_endpoint() {
    local endpoint=$1
    local authority
    local scheme
    local host_port

    [[ $endpoint =~ ^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+) ]] || fail 'request.endpoint must be an absolute URL with a host.' || return
    scheme=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
    authority=${BASH_REMATCH[2]#*@}
    if [[ $authority =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
        TCP_HOST=${BASH_REMATCH[1]}
        TCP_PORT=${BASH_REMATCH[2]}
    elif [[ $authority =~ ^([^:]+):([0-9]+)$ ]]; then
        TCP_HOST=${BASH_REMATCH[1]}
        TCP_PORT=${BASH_REMATCH[2]}
    elif [[ $authority != *:* && $scheme == http ]]; then
        TCP_HOST=$authority
        TCP_PORT=80
    elif [[ $authority != *:* && $scheme == https ]]; then
        TCP_HOST=$authority
        TCP_PORT=443
    else
        fail 'request.endpoint must specify a valid TCP port.' || return
    fi
    [[ $TCP_PORT =~ ^[0-9]+$ ]] && ((TCP_PORT >= 1 && TCP_PORT <= 65535)) || fail 'request.endpoint must specify a valid TCP port.'
}