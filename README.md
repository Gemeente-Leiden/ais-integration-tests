<div align="right">
    <img src="docs/media/logo.png" alt="Gemeente-Leiden" width="64" >
</div>

# AIS integration tests

PowerShell and Bash tools for testing protected HTTP APIs with OAuth 2.0 or mTLS. A
request is defined in a JSON file, so multiple endpoints and payloads can be
maintained as separate test configurations.

The repository provides four test modes:

| Command | Description |
| --- | --- |
| `test-single` | Sends one request and prints the request and response. |
| `test-interval` | Starts a concurrent batch at a fixed interval. |
| `test-rate` | Distributes requests at a configured requests-per-second rate. |
| `test-tcp` | Checks whether a TCP connection can be opened to the request endpoint. |

## Prerequisites

- PowerShell 7 or newer (`pwsh`)
- Bash 3.2 or newer, `jq`, `curl`, and `nc` for Bash runners
- Network access to the OAuth token endpoint, when using OAuth 2.0
- Network access to the target API
- OAuth client credentials, when using OAuth 2.0
- A client certificate in PFX format, when using mTLS
- An API subscription key if required by the configured API

Run all commands from the repository root.

## Setup

Environment variables can be set explicitly in the current process or loaded
from a local secrets file. To use a file, copy the example:

```powershell
Copy-Item .env.example .env
```

```bash
cp .env.example .env
```

> **Warning:** `.env` is ignored by Git. Do not commit credentials. If credentials were ever
> committed, remove them from Git history where appropriate and rotate them.

Fill in these values in `.env`:

```dotenv
OAUTH2_CLIENT_ID=replace-with-client-id
OAUTH2_CLIENT_SECRET=replace-with-client-secret
OAUTH2_SCOPE=replace-with-scope/.default
OAUTH2_TOKEN_URL=https://login.microsoftonline.com/replace-with-tenant-id/oauth2/v2.0/token
MTLS_CERTIFICATE_PATH=replace-with-client-certificate-pfx-path
MTLS_CERTIFICATE_PASSWORD=replace-with-client-certificate-password
APIM_SUBSCRIPTION_KEY=replace-with-subscription-key
```

For each HTTP request configuration, the runner searches for the closest `.env`
file from the configuration file's directory upward to the filesystem root. For
example, `tests/prod/brp-personen.json` uses `tests/prod/.env` when it exists,
while `tests/dev/brp-personen.json` uses the repository-root `.env` when there
is no closer file. When no `.env` file is found, the existing process
environment is used unchanged.

## Request configuration

Each run uses a request configuration file that defines the request endpoint,
method, headers, body and runner configurations.

```json
{
    "request": {
        "endpoint": "https://api.example.nl/resource",
        "method": "POST",
        "headers": {
            "Ocp-Apim-Subscription-Key": "${APIM_SUBSCRIPTION_KEY}",
            "Content-Type": "application/json"
        },
        "body": {
            "example": true
        }
    },
    "interval": {
        "seconds": 10,
        "concurrentExecutions": 10,
        "durationSeconds": 60,
        "percentiles": [80, 90, 95]
    },
    "rate": {
        "requestsPerSecond": 10,
        "durationSeconds": 30,
        "percentiles": [80, 90, 95]
    }
}
```

See `tests/dev/brp-personen.json` for a working example.

### Request properties

| Property | Required | Description |
| --- | --- | --- |
| `request.endpoint` | Yes | Absolute URL of the API endpoint. |
| `request.method` | Yes | HTTP method, such as `GET`, `POST`, or `PATCH`. |
| `request.headers` | Yes | JSON object containing request headers. |
| `request.body` | No | JSON value or raw string sent as the request body. |

The request body supports the following forms:

- Omitted or `null`: no `Body` parameter is sent.
- Empty string (`""`): an explicitly empty body is sent.
- String: the raw string is sent unchanged.
- Object, array, number, or boolean: the value is serialized as JSON.

### Placeholders

Strings in request headers and bodies can reference environment variables using
`${NAME}`. The following placeholders are commonly used:

- `${APIM_SUBSCRIPTION_KEY}`

An unresolved or empty placeholder stops the run with an error.

## Authentication

All runs except the TCP connection test support the `-AuthenticationType`
parameter to control authentication to the specified endpoint. It supports the
following values:

| Authentication type | Description | Relevant environment variable(s) |
| --- | --- | --- |
| `OAuth2` | Retrieves an OAuth 2.0 access token and injects the `Authorization` header automatically. This is the default. | `OAUTH2_CLIENT_ID`, `OAUTH2_CLIENT_SECRET`, `OAUTH2_SCOPE`, `OAUTH2_TOKEN_URL` |
| `mTLS` | Sends the request with the client certificate from `MTLS_CERTIFICATE_PATH` (PFX). No OAuth token is retrieved. | `MTLS_CERTIFICATE_PATH`, `MTLS_CERTIFICATE_PASSWORD` (only needed when the PFX file is password protected) |

## Run a single request

To execute a single request, run the following script:

```powershell
./test-single.ps1
```

```bash
./test-single.sh
```

> **Warning:** Request output includes resolved headers, including authorization
> and subscription credentials. Do not share terminal output without redacting
> sensitive values.

### Parameters

This script accepts the following parameters:

| PowerShell | Bash | Description |
| --- | --- | --- |
| `-ConfigPath` | `--config-path` | Path to the request configuration file. When omitted, the script prompts you to choose one from `tests/`. |
| `-AuthenticationType` | `--authentication-type` | Authentication method. Supported values are `OAuth2` (default) and `mTLS`. |
| `-SkipCertificateCheck` | `--skip-certificate-check` | Disables TLS certificate validation for this run. Use only in trusted test environments. |

## Run an interval test

To execute an interval test, run the following script:

```powershell
./test-interval.ps1
```

```bash
./test-interval.sh
```

### Parameters

This script accepts the following parameters:

| PowerShell | Bash | Description |
| --- | --- | --- |
| `-ConfigPath` | `--config-path` | Path to the request configuration file. When omitted, the script prompts you to choose one from `tests/`. |
| `-AuthenticationType` | `--authentication-type` | Authentication method. Supported values are `OAuth2` (default) and `mTLS`. |
| `-SkipCertificateCheck` | `--skip-certificate-check` | Disables TLS certificate validation for this run. Use only in trusted test environments. |

### Request configuration

The `interval` object in the chosen request configuration controls the run:

| Property | Description |
| --- | --- |
| `seconds` | Time between the start of each batch. Must be positive. |
| `concurrentExecutions` | Requests started in each batch. Must be positive. |
| `durationSeconds` | Time during which new batches are scheduled. Must be positive. |
| `percentiles` | Percentiles to report; each value must be between 1 and 100. |

For example, a 60-second test with an interval of 10 seconds and concurrency of
10 schedules a batch of 10 requests at approximately 0, 10, 20, 30, 40, and 50
seconds. The script waits for all scheduled requests to finish after scheduling
stops.

## Run a rate test

To execute a rate test, run the following script:

```powershell
./test-rate.ps1
```

```bash
./test-rate.sh
```

### Parameters

This script accepts the following parameters:

| PowerShell | Bash | Description |
| --- | --- | --- |
| `-ConfigPath` | `--config-path` | Path to the request configuration file. When omitted, the script prompts you to choose one from `tests/`. |
| `-AuthenticationType` | `--authentication-type` | Authentication method. Supported values are `OAuth2` (default) and `mTLS`. |
| `-SkipCertificateCheck` | `--skip-certificate-check` | Disables TLS certificate validation for this run. Use only in trusted test environments. |

### Request configuration

The `rate` object in the chosen request configuration controls the run:

| Property | Description |
| --- | --- |
| `requestsPerSecond` | Number of requests scheduled per second. Must be positive. |
| `durationSeconds` | Time during which requests are scheduled. Must be positive. |
| `percentiles` | Percentiles to report; each value must be between 1 and 100. |

Requests are spaced evenly throughout each second. The intended number of
requests is `requestsPerSecond * durationSeconds`. Scheduling overhead can cause
fewer requests to start when the local machine cannot keep up with the requested
rate.

## Run a TCP connection test

To execute a TCP connection test, run the following script:

```powershell
./test-tcp.ps1
```

```bash
./test-tcp.sh
```

The script reports the selected host and port and the connection duration. A
refused, timed-out, or otherwise failed connection returns a nonzero exit code.

### Parameters

This script accepts the following parameters:

| PowerShell | Bash | Description |
| --- | --- | --- |
| `-ConfigPath` | `--config-path` | Path to the request configuration file. When omitted, the script prompts you to choose one from `tests/`. |
| `-TimeoutSeconds` | `--timeout-seconds` | Connection timeout for the TCP check, from 1 to 300 seconds. Defaults to 10 seconds. |

### Request configuration

The TCP test reads `request.endpoint` from the chosen request configuration,
extracts its host and port, and attempts one TCP connection. It does not
retrieve an OAuth token, load `.env`, send HTTP headers, or send a request body.

HTTP and HTTPS URLs use their standard ports when no port is specified: port 80
for HTTP and port 443 for HTTPS. Other URI schemes must include an explicit
port, for example `tcp://service.example.nl:8443`.

## Results and timing

Interval and rate tests report:

- Total, successful, and failed executions
- Average request duration
- Every configured request-duration percentile

Only the main API request is timed. OAuth token retrieval, configuration parsing,
request construction, scheduling, and output are excluded. One access token is
retrieved before each run and reused for all requests in that run.

Percentiles use the nearest-rank method. Statistics include executions that
completed without a PowerShell exception. Because HTTP error responses are
captured instead of thrown, a non-2xx HTTP status is not currently counted as an
execution failure.

The interval and rate scripts exit with code `1` when one or more executions
throw an error. Configuration and authentication errors also terminate the run.

## Multiple configurations

Multiple independent request configuration files can be stored under `tests/`.

```powershell
./test-single.ps1 -ConfigPath ./tests/request-a.json
./test-single.ps1 -ConfigPath ./tests/request-b.json
```

```bash
./test-single.sh --config-path ./tests/request-a.json
./test-single.sh --config-path ./tests/request-b.json
```

Both relative and absolute paths are supported. A configuration used by the
interval runner must contain an `interval` object; a configuration used by the
rate runner must contain a `rate` object. Explicit configuration paths may also
point outside the repository.

## Security notes

- Use `-SkipCertificateCheck` or `--skip-certificate-check` only in an
    environment where bypassing TLS certificate validation is explicitly
    acceptable.
- Keep `.env` local and rotate credentials if they may have been exposed.
- Start with low concurrency and request rates. Confirm that load testing is
    permitted for the target environment before increasing them.
