#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIRECTORY/lib/config.sh"
. "$SCRIPT_DIRECTORY/lib/json.sh"

main() {
    local config_path=''
    local timeout_seconds=10
    local configuration_path
    local endpoint
    local nc_help
    local timing_file
    local duration_seconds
    local TIMEFORMAT='%3R'

    while (($# > 0)); do
        case $1 in
            --config-path) config_path=$2; shift 2 ;;
            --timeout-seconds) timeout_seconds=$2; shift 2 ;;
            *) fail "Unknown argument: $1" || return ;;
        esac
    done
    [[ $timeout_seconds =~ ^[0-9]+$ ]] && ((timeout_seconds >= 1 && timeout_seconds <= 300)) || fail '--timeout-seconds must be between 1 and 300.' || return
    require_command jq || return
    require_command nc || return
    configuration_path=$(resolve_configuration_path "$config_path" "$SCRIPT_DIRECTORY/tests" "$SCRIPT_DIRECTORY") || return
    import_json_file "$configuration_path" || return
    endpoint=$(json_required_string 'request.endpoint') || return
    get_tcp_endpoint "$endpoint" || return

    printf 'Testing TCP connection to %s:%s.\n' "$TCP_HOST" "$TCP_PORT"
    nc_help=$(nc -h 2>&1 || true)
    timing_file=$(mktemp "${TMPDIR:-/tmp}/ais-tcp-time.XXXXXX") || return
    trap 'rm -f "$timing_file"' RETURN
    if [[ $nc_help == *-G* ]]; then
        { time nc -z -G "$timeout_seconds" "$TCP_HOST" "$TCP_PORT"; } 2> "$timing_file"
    else
        { time nc -z -w "$timeout_seconds" "$TCP_HOST" "$TCP_PORT"; } 2> "$timing_file"
    fi || {
        fail 'TCP connection failed.'
        return
    }
    duration_seconds=$(tail -n 1 "$timing_file")
    [[ $duration_seconds =~ ^[0-9]+(\.[0-9]+)?$ ]] || fail 'Could not measure TCP connection duration.' || return
    awk -v seconds="$duration_seconds" 'BEGIN { printf "TCP connection succeeded in %.2f ms.\n", seconds * 1000 }'
}

main "$@"