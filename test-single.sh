#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIRECTORY/lib/config.sh"
. "$SCRIPT_DIRECTORY/lib/env.sh"
. "$SCRIPT_DIRECTORY/lib/json.sh"
. "$SCRIPT_DIRECTORY/lib/api.sh"
. "$SCRIPT_DIRECTORY/lib/runner.sh"

main() {
    local configuration_path
    local response_directory

    parse_api_arguments "$@" || return
    configuration_path=$(resolve_configuration_path "$CONFIG_PATH" "$SCRIPT_DIRECTORY/tests" "$SCRIPT_DIRECTORY") || return
    prepare_api_run "$configuration_path" || return
    write_request_details

    response_directory=$(mktemp -d "${TMPDIR:-/tmp}/ais-single.XXXXXX") || return
    trap 'rm -rf "$response_directory"' RETURN
    invoke_api_request "$response_directory/body" "$response_directory/headers" "$response_directory/status" "$SKIP_CERTIFICATE_CHECK" || return
    write_response_details "$response_directory/body" "$response_directory/headers" "$response_directory/status"
}

main "$@"