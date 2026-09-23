#!/usr/bin/env bash

get_oauth_access_token() {
    local basic_authentication
    local response

    assert_required_environment_variables OAUTH2_CLIENT_ID OAUTH2_CLIENT_SECRET OAUTH2_SCOPE OAUTH2_TOKEN_URL || return
    basic_authentication=$(printf '%s:%s' "$OAUTH2_CLIENT_ID" "$OAUTH2_CLIENT_SECRET" | base64 | tr -d '\n')
    response=$(curl --silent --show-error --request POST "$OAUTH2_TOKEN_URL" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header "Authorization: Basic $basic_authentication" \
        --data-urlencode 'grant_type=client_credentials' \
        --data-urlencode "scope=$OAUTH2_SCOPE") || return
    ACCESS_TOKEN=$(printf '%s' "$response" | jq -er '.access_token | select(type == "string" and length > 0)') || {
        fail 'No access token found in OAuth2 response.'
        return
    }
}

get_api_authentication_configuration() {
    local authentication_type=$1

    ACCESS_TOKEN=''
    CLIENT_CERTIFICATE_PATH=''
    CLIENT_CERTIFICATE_PASSWORD=''
    case $authentication_type in
        OAuth2) get_oauth_access_token ;;
        mTLS)
            assert_required_environment_variables MTLS_CERTIFICATE_PATH || return
            [[ -f $MTLS_CERTIFICATE_PATH ]] || fail "Missing mTLS certificate file: $MTLS_CERTIFICATE_PATH" || return
            CLIENT_CERTIFICATE_PATH=$MTLS_CERTIFICATE_PATH
            CLIENT_CERTIFICATE_PASSWORD=${MTLS_CERTIFICATE_PASSWORD:-}
            ;;
        *) fail "Unsupported authentication type: $authentication_type" ;;
    esac
}

add_authorization_bearer_token_header() {
    [[ -z $ACCESS_TOKEN ]] || REQUEST_HEADERS_JSON=$(printf '%s' "$REQUEST_HEADERS_JSON" | jq -c --arg token "$ACCESS_TOKEN" '.Authorization = "Bearer " + $token')
}

build_request_header_arguments() {
    REQUEST_HEADER_ARGUMENTS=()
    local header
    while IFS= read -r header; do
        REQUEST_HEADER_ARGUMENTS[${#REQUEST_HEADER_ARGUMENTS[@]}]='--header'
        REQUEST_HEADER_ARGUMENTS[${#REQUEST_HEADER_ARGUMENTS[@]}]=$header
    done < <(printf '%s' "$REQUEST_HEADERS_JSON" | jq -r 'to_entries[] | "\(.key): \(.value | tostring)"')
}

write_request_details() {
    printf '\nRequest:\nMethod: %s\nUri: %s\nRequest headers:\n' "$REQUEST_METHOD" "$REQUEST_ENDPOINT"
    printf '%s' "$REQUEST_HEADERS_JSON" | jq -r 'to_entries | sort_by(.key)[] | "\(.key): \(.value)"'
    printf 'Request body:\n'
    if [[ $REQUEST_HAS_BODY == true ]]; then
        if printf '%s' "$REQUEST_BODY" | jq . >/dev/null 2>&1; then
            printf '%s' "$REQUEST_BODY" | jq .
        else
            printf '%s\n' "$REQUEST_BODY"
        fi
        printf '\n'
    else
        printf '(none)\n\n'
    fi
}

invoke_api_request() {
    local response_body_file=$1
    local response_headers_file=$2
    local status_file=$3
    local skip_certificate_check=$4
    local curl_arguments=(--silent --show-error --request "$REQUEST_METHOD" --dump-header "$response_headers_file" --output "$response_body_file" --write-out '%{http_code} %{time_total}')
    local result

    curl_arguments+=("${REQUEST_HEADER_ARGUMENTS[@]}")
    [[ $skip_certificate_check == true ]] && curl_arguments+=(--insecure)
    [[ -n $CLIENT_CERTIFICATE_PATH ]] && curl_arguments+=(--cert "$CLIENT_CERTIFICATE_PATH${CLIENT_CERTIFICATE_PASSWORD:+:$CLIENT_CERTIFICATE_PASSWORD}" --cert-type P12)
    [[ $REQUEST_HAS_BODY == true ]] && curl_arguments+=(--data-binary "$REQUEST_BODY")
    result=$(curl "${curl_arguments[@]}" "$REQUEST_ENDPOINT") || return
    printf '%s\n' "$result" > "$status_file"
}

write_response_details() {
    local response_body_file=$1
    local response_headers_file=$2
    local status_file=$3
    local status_and_time
    local status
    local duration_seconds

    status_and_time=$(cat "$status_file")
    status=${status_and_time%% *}
    duration_seconds=${status_and_time#* }
    printf 'Response status: %s\nResponse headers:\n' "$status"
    sed 's/\r$//' "$response_headers_file"
    printf 'Response body:\n'
    if [[ -s $response_body_file ]]; then
        if jq . "$response_body_file" >/dev/null 2>&1; then jq . "$response_body_file"; else cat "$response_body_file"; fi
    else
        printf 'null\n'
    fi
    awk -v seconds="$duration_seconds" 'BEGIN { printf "\nDuration: %.2f ms\n\n", seconds * 1000 }'
}