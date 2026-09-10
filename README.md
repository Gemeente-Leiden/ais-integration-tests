<div align="right">
    <img src="docs/media/logo.png" alt="Gemeente-Leiden" width="64" >
</div>

# AIS integration tests

PowerShell tools for testing OAuth 2.0-protected HTTP APIs. A request is
defined in a JSON file, so multiple endpoints and payloads can be maintained as
separate test configurations.

The repository provides four test modes:

- `test-single.ps1` sends one request and prints the request and response.
- `test-interval.ps1` starts a concurrent batch at a fixed interval.
- `test-rate.ps1` distributes requests at a configured requests-per-second rate.
- `test-tcp.ps1` checks whether a TCP connection can be opened to the request endpoint.

## Prerequisites

- PowerShell 7 or newer (`pwsh`)
- Network access to the OAuth token endpoint and target API
- OAuth client credentials
- An API subscription key if required by the configured API

Run all commands from the repository root.

## Setup

Create the local secrets file from the example:

```powershell
Copy-Item .env.example .env
```

Fill in these values in `.env`:

```dotenv
OAUTH2_CLIENT_ID=replace-with-client-id
OAUTH2_CLIENT_SECRET=replace-with-client-secret
OAUTH2_SCOPE=replace-with-scope/.default
OAUTH2_TOKEN_URL=https://login.microsoftonline.com/replace-with-tenant-id/oauth2/v2.0/token
APIM_SUBSCRIPTION_KEY=replace-with-subscription-key
```

`.env` is ignored by Git. Do not commit credentials. If credentials were ever
committed, remove them from Git history where appropriate and rotate them.

## Request configuration

Each run requires `-ConfigPath` with a path to a JSON configuration file. See
`tests/brp-personen.json` for a working example.

```json
{
    "request": {
        "endpoint": "https://api.example.nl/resource",
        "method": "POST",
        "headers": {
            "Ocp-Apim-Subscription-Key": "${APIM_SUBSCRIPTION_KEY}",
            "Content-Type": "application/json",
            "Authorization": "Bearer ${ACCESS_TOKEN}"
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

- `${ACCESS_TOKEN}` is provided automatically after OAuth authentication.
- `${APIM_SUBSCRIPTION_KEY}` is read from `.env`.
- Any other `${NAME}` is resolved from the current process environment.

An unresolved or empty placeholder stops the run with an error.

## Run a single request

```powershell
./test-single.ps1 -ConfigPath ./tests/brp-personen.json
```

To disable TLS certificate validation for a run, add the optional switch:

```powershell
./test-single.ps1 -ConfigPath ./tests/brp-personen.json -SkipCertificateCheck
```

The single test prints the request method, endpoint, headers, body, response
status, response headers, and response body.

> **Warning:** Request output includes resolved headers, including authorization
> and subscription credentials. Do not share terminal output without redacting
> sensitive values.

## Run an interval test

```powershell
./test-interval.ps1 -ConfigPath ./tests/brp-personen.json
./test-interval.ps1 -ConfigPath ./tests/brp-personen.json -SkipCertificateCheck
```

The `interval` object controls the run:

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

```powershell
./test-rate.ps1 -ConfigPath ./tests/brp-personen.json
./test-rate.ps1 -ConfigPath ./tests/brp-personen.json -SkipCertificateCheck
```

The `rate` object controls the run:

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

```powershell
./test-tcp.ps1 -ConfigPath ./tests/brp-personen.json
```

The TCP test reads `request.endpoint`, extracts its host and port, and attempts
one TCP connection. It does not retrieve an OAuth token, load `.env`, send HTTP
headers, or send a request body.

HTTP and HTTPS URLs use their standard ports when no port is specified: port 80
for HTTP and port 443 for HTTPS. Other URI schemes must include an explicit
port, for example `tcp://service.example.nl:8443`.

The default connection timeout is 10 seconds. Set a value from 1 through 300
seconds with `-TimeoutSeconds`:

```powershell
./test-tcp.ps1 -ConfigPath ./tests/brp-personen.json -TimeoutSeconds 5
```

The script reports the selected host and port and the connection duration. A
refused, timed-out, or otherwise failed connection returns a nonzero exit code.

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

Store independent JSON files under `tests/` or another directory and select one
at runtime:

```powershell
./test-single.ps1 -ConfigPath ./tests/request-a.json
./test-single.ps1 -ConfigPath ./tests/request-b.json
```

Both relative and absolute paths are supported. A configuration used by the
interval runner must contain an `interval` object; a configuration used by the
rate runner must contain a `rate` object.

## Security notes

- Use `-SkipCertificateCheck` only in an environment where
    bypassing TLS certificate validation is explicitly acceptable.
- Keep `.env` local and rotate credentials if they may have been exposed.
- Start with low concurrency and request rates. Confirm that load testing is
    permitted for the target environment before increasing them.
