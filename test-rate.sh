#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIRECTORY/lib/config.sh"
. "$SCRIPT_DIRECTORY/lib/env.sh"
. "$SCRIPT_DIRECTORY/lib/json.sh"
. "$SCRIPT_DIRECTORY/lib/api.sh"
. "$SCRIPT_DIRECTORY/lib/stats.sh"
. "$SCRIPT_DIRECTORY/lib/runner.sh"

main() {
    local configuration_path
    local requests_per_second
    local duration_seconds
    local total_requests
    local results_directory
    local percentiles_file
    local execution_number
    local scheduled_delay
    local start_seconds
    local pids=()
    local pid

    parse_api_arguments "$@" || return
    configuration_path=$(resolve_configuration_path "$CONFIG_PATH" "$SCRIPT_DIRECTORY/tests" "$SCRIPT_DIRECTORY") || return
    prepare_api_run "$configuration_path" || return
    requests_per_second=$(json_positive_integer 'rate.requestsPerSecond') || return
    duration_seconds=$(json_positive_integer 'rate.durationSeconds') || return
    total_requests=$((requests_per_second * duration_seconds))
    results_directory=$(mktemp -d "${TMPDIR:-/tmp}/ais-rate.XXXXXX") || return
    trap 'rm -rf "$results_directory"' RETURN
    percentiles_file=$results_directory/percentiles
    json_integer_list 'rate.percentiles' 1 100 > "$percentiles_file" || return

    printf 'Running at %s request(s) per second for %s second(s).\n' "$requests_per_second" "$duration_seconds"
    start_seconds=$SECONDS
    for ((execution_number = 1; execution_number <= total_requests; execution_number++)); do
        ((SECONDS - start_seconds >= duration_seconds)) && break
        execute_request_to_result "$results_directory/result-$execution_number" &
        pids[${#pids[@]}]=$!
        scheduled_delay=$(awk -v rate="$requests_per_second" 'BEGIN { printf "%.6f", 1 / rate }')
        sleep "$scheduled_delay"
    done

    printf 'All %d execution(s) scheduled. Collecting results.\n' "${#pids[@]}"
    for pid in "${pids[@]}"; do wait "$pid" || true; done
    write_execution_summary "$results_directory" "$percentiles_file"
}

main "$@"