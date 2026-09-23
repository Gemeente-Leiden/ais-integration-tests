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
    local interval_seconds
    local concurrent_executions
    local duration_seconds
    local results_directory
    local percentiles_file
    local execution_number=0
    local batch_number=0
    local batch_start=0
    local index
    local pids=()
    local pid

    parse_api_arguments "$@" || return
    configuration_path=$(resolve_configuration_path "$CONFIG_PATH" "$SCRIPT_DIRECTORY/tests" "$SCRIPT_DIRECTORY") || return
    prepare_api_run "$configuration_path" || return
    interval_seconds=$(json_positive_integer 'interval.seconds') || return
    concurrent_executions=$(json_positive_integer 'interval.concurrentExecutions') || return
    duration_seconds=$(json_positive_integer 'interval.durationSeconds') || return
    results_directory=$(mktemp -d "${TMPDIR:-/tmp}/ais-interval.XXXXXX") || return
    trap 'rm -rf "$results_directory"' RETURN
    percentiles_file=$results_directory/percentiles
    json_integer_list 'interval.percentiles' 1 100 > "$percentiles_file" || return

    printf 'Running for %s second(s): %s execution(s) every %s second(s).\n' "$duration_seconds" "$concurrent_executions" "$interval_seconds"
    while ((batch_start < duration_seconds)); do
        ((batch_number++))
        printf 'Starting batch %d with %s concurrent execution(s).\n' "$batch_number" "$concurrent_executions"
        for ((index = 0; index < concurrent_executions; index++)); do
            ((execution_number++))
            execute_request_to_result "$results_directory/result-$execution_number" &
            pids[${#pids[@]}]=$!
        done
        batch_start=$((batch_start + interval_seconds))
        ((batch_start < duration_seconds)) && sleep "$interval_seconds"
    done

    printf 'All %d execution(s) scheduled. Collecting results.\n' "${#pids[@]}"
    for pid in "${pids[@]}"; do wait "$pid" || true; done
    write_execution_summary "$results_directory" "$percentiles_file"
}

main "$@"