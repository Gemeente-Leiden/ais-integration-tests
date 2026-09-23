#!/usr/bin/env bash

parse_api_arguments() {
    CONFIG_PATH=''
    AUTHENTICATION_TYPE='OAuth2'
    SKIP_CERTIFICATE_CHECK=false

    while (($# > 0)); do
        case $1 in
            --config-path)
                (($# >= 2)) || fail 'Missing value for --config-path' || return
                CONFIG_PATH=$2
                shift 2
                ;;
            --authentication-type)
                (($# >= 2)) || fail 'Missing value for --authentication-type' || return
                AUTHENTICATION_TYPE=$2
                shift 2
                ;;
            --skip-certificate-check)
                SKIP_CERTIFICATE_CHECK=true
                shift
                ;;
            *) fail "Unknown argument: $1" || return ;;
        esac
    done

    [[ $AUTHENTICATION_TYPE == OAuth2 || $AUTHENTICATION_TYPE == mTLS ]] || fail "Unsupported authentication type: $AUTHENTICATION_TYPE"
}

prepare_api_run() {
    local configuration_path=$1
    local environment_file

    require_command jq || return
    require_command curl || return
    import_json_file "$configuration_path" || return
    environment_file=$(resolve_environment_file_path "$configuration_path") || return
    import_environment_file "$environment_file" || return
    assert_required_environment_variables APIM_SUBSCRIPTION_KEY || return
    get_api_authentication_configuration "$AUTHENTICATION_TYPE" || return
    get_json_request_configuration || return
    add_authorization_bearer_token_header || return
    build_request_header_arguments
}

execute_request_to_result() {
    local result_file=$1
    local execution_directory
    local status_and_time
    local duration_seconds
    local duration_milliseconds

    execution_directory=$(mktemp -d "${TMPDIR:-/tmp}/ais-request.XXXXXX") || return
    if invoke_api_request "$execution_directory/body" "$execution_directory/headers" "$execution_directory/status" "$SKIP_CERTIFICATE_CHECK"; then
        status_and_time=$(cat "$execution_directory/status")
        duration_seconds=${status_and_time#* }
        duration_milliseconds=$(awk -v seconds="$duration_seconds" 'BEGIN { printf "%.6f", seconds * 1000 }')
        printf 'succeeded\t%s\n' "$duration_milliseconds" > "$result_file"
    else
        printf 'failed\n' > "$result_file"
    fi
    rm -rf "$execution_directory"
}

write_execution_summary() {
    local results_directory=$1
    local percentiles_file=$2
    local result_file
    local total=0
    local succeeded=0
    local failed=0
    local status
    local duration
    local durations_file=$results_directory/durations
    local percentiles=()

    : > "$durations_file"
    for result_file in "$results_directory"/result-*; do
        [[ -f $result_file ]] || continue
        total=$((total + 1))
        IFS=$'\t' read -r status duration < "$result_file"
        if [[ $status == succeeded ]]; then
            succeeded=$((succeeded + 1))
            printf '%s\n' "$duration" >> "$durations_file"
        else
            failed=$((failed + 1))
        fi
    done
    while IFS= read -r duration; do
        percentiles[${#percentiles[@]}]=$duration
    done < "$percentiles_file"

    printf 'Finished: %d total, %d succeeded, %d failed.\n' "$total" "$succeeded" "$failed"
    write_duration_statistics "$durations_file" "${percentiles[@]}"
    ((failed == 0))
}