# API Reference Overview

## Base URL

All v2.0 API endpoints are available at:

```
https://<YOUR_SERVER>:8714/v2.0/
```

Replace `<YOUR_SERVER>` with your Password Depot Server's hostname or IP address. The default port is **8714**.

### Entry Icons

An entry or folder shows one of two kinds of icon.

**Standard icons.** The 135 icons that ship with Password Depot are served at a separate path outside the API version prefix:

```
https://<YOUR_SERVER>:8714/file/<filename>
```

Each entry and folder has an `icon` field that names one of them - always `ico0.svg` to `ico134.svg`. **No authentication is required** for these requests, and from Server 20.0.0 on the path serves nothing else: only `GET` and `HEAD`, only those 135 names (in any letter case), as `image/svg+xml`; any other name answers `404`. The files are single-colour SVG templates that take their colour from the page (`currentColor`), so a client may just as well bundle its own set and use `icon` only as the number.

**Example:** `https://<YOUR_SERVER>:8714/file/ico12.svg`

**Database icons.** *Server 20.0.0 and later.* Images that belong to one database - what the Windows client calls custom icons - are never served from `/file/`. They are per database, need a bearer token like everything else under `/v2.0/`, and travel as Base64 inside JSON; see [Database Icons](icons.md). An entry or folder that uses one names it in its `database_icon` field, and its `icon` field then names the standard icon to fall back on.

**Fallback chain.** Show the `database_icon` image when the field is not `null` and the image can be fetched; otherwise the standard icon named by `icon`; otherwise your client's own symbol for the item's `type`.

## Authentication

All endpoints require an `Authorization: Bearer <token>` header, **except**:

- `POST /v2.0/auth/login` -- obtain a token (supports `standard`, `sspi`, `negotiate`, `oidc`, and `azure` auth methods)
- `POST /v2.0/auth/webauthn/begin` -- begin a WebAuthn/Passkey authentication
- `POST /v2.0/auth/webauthn/complete` -- complete a WebAuthn/Passkey authentication
- `GET /v2.0/auth/oidc` -- discover OIDC providers

Include the header on every authenticated request:

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

The token expires after **10 minutes of inactivity**. Each successful request resets the timer.

## Request Format

- All request bodies must be **JSON** with `Content-Type: application/json`
- Every request body must state its size in a `Content-Length` header. A request that carries a `Transfer-Encoding` header - whether or not it also sends a `Content-Length` - is refused with `411 Length Required` before the body is read (*Server 20.0.0 and later*); see [Length required (`411`)](#http-status-codes) below
- Character encoding: **UTF-8**
- Query parameters are passed in the URL
- The binary content upload (`PUT .../entries/{id}/content`) handles documents and, from Server 20.0.0, certificate public/private files. A [database icon](icons.md#upload-icon) is uploaded as JSON, with the image as Base64 in the `data` field - there is no multipart or binary icon upload

## Response Format

All responses are returned as **JSON** with native types:

- Booleans: `true` / `false` (not `"1"` / `"0"` as in v1.0)
- Integers: `42` (not `"42"`)
- Dates: ISO 8601 format (e.g., `"2024-11-20T16:45:00.000Z"`)

### Cache Headers

Every API response includes the headers `Cache-Control: no-store` and `Pragma: no-cache`. This applies to all `/v2.0` and `/v1.0` endpoints, `/file` and `/temp` downloads, `OPTIONS` preflight responses, and JSON error responses. API responses can carry plaintext secrets (entry passwords, shared-secret values, second-password-decrypted fields), so they must never be written to a shared or browser disk cache. The shared-link HTML page (`GET /shared/...`) uses the slightly stricter `Cache-Control: no-cache, no-store`. These headers do not change any status code or response body.

## Pagination

All list endpoints support pagination via query parameters:

| Parameter | Type | Default | Allowed range | Description |
|-----------|------|---------|---------------|-------------|
| `offset` | integer | `0` | `>= 0` | Number of items to skip |
| `limit` | integer | `100` | `1..1000` | Maximum number of items to return |

**Validation rules:**

- Non-integer or overflowing values (e.g., `limit=abc`, `offset=9999999999999999999`) → `400 Bad Request`.
- `offset < 0` or `limit < 1` → `400 Bad Request`.
- `limit > 1000` is **silently clamped** to `1000`. The response echoes the clamped value (e.g., `"limit": 1000`) so clients can detect it. Iterate with multiple requests for larger result sets.

**Example request:**

```
GET /v2.0/databases?offset=0&limit=100
```

**Paginated response envelope:**

```json
{
  "data": [
    { "id": "...", "name": "..." },
    { "id": "...", "name": "..." }
  ],
  "total": 125,
  "offset": 0,
  "limit": 100
}
```

| Field | Type | Description |
|-------|------|-------------|
| `data` | array | Array of resource objects for the current page |
| `total` | integer | Total number of items across all pages |
| `offset` | integer | The offset used for this request |
| `limit` | integer | The **effective** limit used for this request (may differ from the request value if clamped) |

!!! tip "Fetching All Results"
    To retrieve all items, increment `offset` by `limit` until `offset >= total`:
    ```
    GET /v2.0/admin/users?offset=0&limit=100    → items 1-100
    GET /v2.0/admin/users?offset=100&limit=100  → items 101-125
    ```

## Error Format

On error, the server returns a JSON object with a nested `error` object:

```json
{
  "error": {
    "code": 404,
    "message": "Entry not found"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `error.code` | integer | HTTP status code, or an application sub-code (see below) |
| `error.message` | string | Human-readable error description |

!!! note "Difference from v1.0"
    v1.0 used a flat format: `{"code": 404, "error": "..."}`. v2.0 uses a nested structure: `{"error": {"code": 404, "message": "..."}}`.

!!! note "Application sub-codes in `error.code`"
    `error.code` usually equals the HTTP status, but it may carry an application sub-code (`>= 1000`) that conveys a finer, machine-readable reason. The **HTTP status is authoritative** for the response class (for example, whether a token was issued); `error.code` only refines it. Always match the numeric code, never the localized message. A client must not infer a specific reason from a sub-code it does not recognise: show a neutral message rather than the reason a plain status would imply -- an unrecognised `401` sub-code on login does not mean the password was wrong.

    | Sub-code | HTTP | Constant | Meaning |
    |:--------:|:----:|----------|---------|
    | `4001` | `400` | `PD_ERRCODE_TOTP_SECRET` | Entry `totp` write: `secret` is not strict Base32 of 16 to 128 characters, or yields no code |
    | `4002` | `400` | `PD_ERRCODE_TOTP_ALGORITHM` | Entry `totp` write: `algorithm` is not `SHA1`, `SHA256` or `SHA512` |
    | `4003` | `400` | `PD_ERRCODE_TOTP_DIGITS` | Entry `totp` write: `digits` outside `6` to `8` |
    | `4004` | `400` | `PD_ERRCODE_TOTP_PERIOD` | Entry `totp` write: `period` outside `15` to `120` |
    | `4005` | `400` | `PD_ERRCODE_TOTP_SHAPE` | Entry `totp` write: wrong shape (`{}`, an unknown member, a wrong JSON type, or no `secret` where one is required) |
    | `4006` | `400` | `PD_ERRCODE_TOTP_ENTRY_TYPE` | Entry `totp` write: the entry's type cannot carry a one-time code written over REST |
    | `4007` | `400` | `PD_ERRCODE_ICON_ASSIGNMENT` | Entry or folder `POST` / `PATCH`: `image_custom`, `image_index` and `image_name` do not name a usable icon; nothing was written |
    | `4008` | `400` | `PD_ERRCODE_ICON_IMAGE` | `POST /databases/{db}/icons`: `data` is not a usable PNG |
    | `4012` | `401` | `PD_ERRCODE_2FA_EMAIL_SEND_FAILED` | Login: e-mail two-factor authentication is required, but the server cannot send the verification e-mail |
    | `4013` | `401` | `PD_ERRCODE_2FA_EMAIL_MISSING` | Login: e-mail two-factor authentication is required, but the account has no e-mail address |
    | `4031` | `403` | `PD_ERRCODE_INVALID_SECOND_PASS` | Wrong or missing second password; a generic access-denied `403` keeps `error.code = 403` |
    | `4032` | `403` | `PD_ERRCODE_LICENSE_LIMIT` | `POST /admin/users`: the server's licensed number of users is reached |
    | `4033` | `403` | `PD_ERRCODE_TOTP_READ_REQUIRED` | Entry `totp` write on `PATCH`: read permission on the entry is required as well |
    | `4034` | `403` | `PD_ERRCODE_ICON_QUOTA` | `POST /databases/{db}/icons`: the database cannot hold another icon |
    | `4035` | `403` | `PD_ERRCODE_ITEM_LOCKED` | `DELETE` of an entry or folder: the item, or something inside the folder, is being edited by another client; nothing was deleted |
    | `4041` | `404` | `PD_ERRCODE_NO_ONE_TIME_CODE` | The entry has no one-time code; a `404` for an entry that does not exist keeps `error.code = 404` |
    | `4042` | `404` | `PD_ERRCODE_ICON_NOT_FOUND` | `GET /databases/{db}/icons/{icon_id}`: no usable icon with that id in this database; a `404` for a database that does not exist keeps `error.code = 404` |
    | `4131` | `413` | `PD_ERRCODE_ICON_TOO_LARGE` | `POST /databases/{db}/icons`: too many bytes, too many pixels, or too large a stored record |

    *Changed in Server 20.0.0.* `4001` to `4008`, `4012`, `4013`, `4032` to `4035`, `4041`, `4042` and `4131` are new. `4035` belongs to [Delete Entry](entries.md#delete-entry) and [Delete Folder](folders.md#delete-folder). `4007`, `4008`, `4034`, `4042` and `4131` belong to [Database Icons](icons.md#sub-codes); `4131` is the first sub-code of the `413` family. Earlier servers answer the two e-mail two-factor conditions with `401` and `error.code` `401`. `4001` to `4006` (see [One-Time Code Settings](entries.md#one-time-code-settings)) are the first sub-codes of the `400` family: a client that recognised a bad request by `error.code == 400` must widen that test to the HTTP status.

## Error Codes

| Code | Name | Description |
|:----:|------|-------------|
| `400` | Bad Request | Invalid request body, missing required fields, or malformed parameters |
| `401` | Unauthorized | Invalid credentials, expired token, or missing `Authorization` header |
| `403` | Forbidden | Authenticated but insufficient permissions for the requested action |
| `404` | Not Found | The requested resource (database, entry, folder, user, etc.) does not exist |
| `409` | Conflict | Resource conflict (e.g., duplicate name, concurrent modification) |
| `410` | Gone | A `/v1.0/` path on Server 20.0.0 or later: REST API v1.0 was removed |
| `411` | Length Required | The request carries a `Transfer-Encoding` header, whether or not it also sends a `Content-Length`. Chunked request bodies are not accepted, and `411` is answered even where `413` would otherwise apply |
| `413` | Payload Too Large | Request body over the limit: 1 MB for JSON bodies, 64 MB for document/certificate content; `4131` for an icon upload over its own, smaller limits |
| `459` | TFA Not Activated | Two-factor authentication needs initial setup (QR code URL returned in `error.message`) |
| `460` | TFA Code Required | A valid 6-digit 2FA code must be provided to complete login |
| `500` | Internal Server Error | Unexpected server-side error |
| `501` | Not Implemented | Operation unsupported for this entry type; for example, one-time codes on `encrypted_file` or `certificate`. These entry types otherwise support REST access from Server 20.0.0 |

## HTTP Methods

| Method | Usage | Typical Response |
|--------|-------|------------------|
| `GET` | Retrieve a resource or list of resources | `200 OK` |
| `POST` | Create a new resource or perform an action (login, logout, move) | `201 Created` or `200 OK` / `204 No Content` |
| `PUT` | Full replacement of a resource's content (used for binary uploads) | `200 OK` |
| `PATCH` | Partial update of an existing resource | `200 OK` |
| `DELETE` | Remove a resource | `204 No Content` |

!!! note "Unsupported methods"
    `HEAD` is not implemented. The server responds with `405 Method Not Allowed` for any method outside the table above, per [RFC 7231 §4.1](https://datatracker.ietf.org/doc/html/rfc7231#section-4.1). If you receive a HEAD response with `Content-Length: 0`, that is the spec-compliant result of the server returning a 405 plus Indy stripping the body (HEAD responses MUST NOT include a message body, per [RFC 7231 §4.3.2](https://datatracker.ietf.org/doc/html/rfc7231#section-4.3.2)). `OPTIONS` is supported only as a CORS preflight -- it returns `204 No Content` with an empty body and the standard CORS headers.

!!! note "Path casing"
    v2.0 URL paths are **case-sensitive** (per [RFC 3986](https://datatracker.ietf.org/doc/html/rfc3986#section-6.2.2.1) and industry convention -- GitHub, Stripe, AWS, etc.). `/v2.0/me` works; `/v2.0/ME` returns `404 Not Found`. This makes WAF/proxy allowlists deterministic and log aggregation reliable. v1.0 retains case-insensitive matching for backward compatibility. HTTP header names, JSON field names, and query parameter names are not affected by this rule.

!!! note "Path slashes"
    A **trailing slash** is accepted and treated as equivalent to the same path without it -- `/v2.0/me` and `/v2.0/me/` both reach the profile endpoint. This is the standard REST convention.

    **Empty path segments in the middle** (e.g. `/v2.0//me`, `/v2.0/admin//users`) are **not** normalized and return `404 Not Found`. Per [RFC 3986 §3.3](https://datatracker.ietf.org/doc/html/rfc3986#section-3.3) a double slash is a distinct path from a single slash; automatically collapsing them would also create a WAF-bypass vector (a proxy that allowlists `/v2.0/users` but not `/v2.0/admin/users` could be bypassed by a server that silently normalizes `/v2.0/admin//users`). Always build your URLs with exactly one slash between segments.

!!! warning "Unknown sub-resources return 404"
    The router performs **strict** sub-resource validation. Any segment past what the endpoint documents causes `404 Not Found`, regardless of HTTP method. Examples:

    ```
    DELETE /v2.0/admin/users/{id}/tfa           -> 404
    DELETE /v2.0/admin/users/{id}/anything      -> 404
    POST   /v2.0/me/password/extra              -> 404
    GET    /v2.0/users/{id}/profile             -> 404
    GET    /v2.0/databases/{id}/search/foo      -> 404
    ```

    This guards against silent-drop bugs where a typo on a destructive call (e.g. `DELETE /admin/users/{id}/passkey` vs `/passkeys`) could target the wrong resource. Only the exact documented paths are accepted.

## HTTP Status Codes

| Code | Meaning | Description |
|:----:|---------|-------------|
| `200` | OK | Request succeeded; response body contains the result |
| `201` | Created | Resource was successfully created; response body contains the new resource |
| `204` | No Content | Request succeeded; no response body (used for DELETE and logout) |
| `400` | Bad Request | Client error in the request |
| `401` | Unauthorized | Authentication required or failed |
| `403` | Forbidden | Insufficient permissions |
| `404` | Not Found | Resource does not exist |
| `405` | Method Not Allowed | HTTP method not supported for this endpoint; `Allow` header lists supported methods |
| `408` | Request Timeout | The request headers stopped arriving part-way through; the connection is closed |
| `409` | Conflict | Resource conflict |
| `410` | Gone | REST API v1.0 path on Server 20.0.0 or later |
| `411` | Length Required | Request body sent with a `Transfer-Encoding` header, with or without a `Content-Length` |
| `413` | Payload Too Large | Request body over the size limit |
| `429` | Too Many Requests | IP lockout / rate limit; see `Retry-After` header |
| `459` | TFA Not Activated | 2FA initial setup required |
| `460` | TFA Code Required | 2FA code needed |
| `500` | Internal Server Error | Server-side failure |
| `501` | Not Implemented | Requested operation is unsupported for the entry type (for example, one-time codes on a certificate) |

!!! info "Method Not Allowed (`405`)"
    When a method is not supported for a given endpoint the server returns `405 Method Not Allowed`, and the response includes an `Allow` header listing the supported methods (per [RFC 7231 §6.5.5](https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.5)).

    ```http
    HTTP/1.1 405 Method Not Allowed
    Allow: GET, POST, PATCH, DELETE
    Content-Type: application/json; charset=utf-8
    ```

    ```json
    {
      "error": {
        "code": 405,
        "message": "Supported methods: GET POST PATCH DELETE"
      }
    }
    ```

    Clients can parse the `Allow` header programmatically to retry with a supported method.

!!! info "IP lockout (`429`)"
    After repeated failed `POST /auth/login` attempts from the same IP address, the server blocks that IP for a configurable period (Server Manager &rarr; *Options* &rarr; *Security* &rarr; *Login Attempts*). While the block is active **every** request from that IP is rejected with `429 Too Many Requests` and a `Retry-After` header containing the number of seconds until the block expires. Clients should honor `Retry-After` and back off; retrying immediately will not shorten the lockout. Login responses with `error.code` `4012` or `4013` do not count as failed attempts (*Server 20.0.0 and later*).

!!! info "Length required (`411`)"
    Every request body must state its size in a `Content-Length` header. A request that carries a `Transfer-Encoding` header - of any value, and whether or not it also sends a `Content-Length`; `chunked` is the one clients send - is refused with `411 Length Required` and `error.code` `411`, while the request headers are being read. The body is never read, the refusal comes before authentication, and the connection is closed afterwards. This applies to every method and every path, including a path that would otherwise answer `404` or `410`, a mirror server's `403` and an address under an IP lockout (*Server 20.0.0 and later*; earlier servers read a chunked body on any route with no size limit at all).

    A request that carries **both** headers answers `411`, not `413`, even when its `Content-Length` is over the limit: the length is not trusted, because it does not describe what would be read.

    ```json
    {
      "error": {
        "code": 411,
        "message": "Send the request body with a Content-Length header. Chunked transfer encoding is not accepted."
      }
    }
    ```

    That payload is the usual JSON error object, but like the `400`, `408` and `413` beside it, it is emitted from the header stage, which cannot set response headers: it is labelled `Content-Type: text/html; charset=utf-8` whatever the bytes are, and carries no CORS or `Cache-Control` headers. A browser reports a network error instead of a status, and a generated client that picks its deserializer from `Content-Type` will not parse it. Match the numeric HTTP status and parse the body without relying on its type.

    A request that sends *neither* header is not refused here, and does not need to be: the server never reads a body whose size was not announced. A `POST` or `PUT` that puts body bytes on the wire without announcing them receives the HTTP layer's own bare `411`, whose body is announced in the response headers but never sent before the connection closes, so most clients report a truncated response rather than the status - unchanged from earlier servers. Nothing refuses a request that announces no length and sends no bytes either, but an endpoint that needs a body then fails it with `500`, because it is dispatched with no body at all: always send a `Content-Length`, `0` included.

    **.NET clients are the common break.** `HttpClient.PostAsJsonAsync`, `JsonContent` and `StreamContent` over a non-seekable stream send `Transfer-Encoding: chunked` by default, so a .NET client hits this on ordinary JSON calls, not only on uploads. Buffer the body so its length is known - `new StringContent(json, Encoding.UTF8, "application/json")`, `ByteArrayContent`, `await content.LoadIntoBufferAsync()`, or a seekable stream. Setting `request.Headers.TransferEncodingChunked = false` does **not** help: the content still has no length for the connection to state, so the request goes out chunked all the same.

    **Other clients that stream** are affected the same way: `curl -T -` (stdin), an explicit `-H "Transfer-Encoding: chunked"`, `Invoke-WebRequest -TransferEncoding chunked`, Python `requests` with a generator body, and Node streams without a length. `curl -T file`, `curl --data-binary @file` and `Invoke-WebRequest -InFile` send a length and keep working.

    **Reverse proxies.** A proxy that forwards request bodies unbuffered - nginx with `proxy_request_buffering off`, and some cloud load balancers - passes the client's own framing through: a client that sent a `Content-Length` still reaches the server with one. What becomes chunked upstream is a body whose length the proxy does not know - a client that streamed its own body, or an HTTP/2 or HTTP/3 front end - and that now receives `411`. Leaving request buffering on (the nginx default) makes the proxy state a length whatever the client did.

!!! info "Payload too large (`413`)"
    The server reads the `Content-Length` header before it reads the body and refuses a request over the limit - 1 MB for JSON bodies, 64 MB for `PUT .../entries/{id}/content` - with `413` and `error.code` `413`. This happens before authentication and before the CORS headers are added, and the connection is closed: a browser reports a network error rather than a status, so a web client must check sizes before it sends. The [icon upload](icons.md#upload-icon) has smaller limits of its own, which it reports as a regular JSON error with `413` and `error.code` `4131`.

!!! info "Content-Length sent twice (`400`)"
    A request that carries **more than one `Content-Length` header** is refused with `400 Bad Request` and `error.code` `400`, while the headers are being read and before the body is read at all, and the connection is closed afterwards ([RFC 7230 &sect;3.3.3](https://datatracker.ietf.org/doc/html/rfc7230#section-3.3.3); *Server 20.0.0 and later*). The two values may agree or disagree; neither is used. Send exactly one.

    This matters because connections are now reused. The server takes the first of the two values; a front end that takes the last one forwards more body bytes than the server reads, and on a persistent connection the remainder would be read as the *next* request on that connection. Refusing the message is the only safe answer. Like the `408`, `411` and `413` beside it, the body is JSON labelled `text/html; charset=utf-8`.

!!! info "Request timeout (`408`)"
    If a request's header block stops arriving part-way through, the server answers `408 Request Timeout` with `error.code` `408` and closes the connection (*Server 20.0.0 and later*). The trigger is silence for longer than the server's idle timeout (15 seconds by default) *between* the start of a request and the blank line that ends its headers; the body is never read, and the request is not dispatched.

    This is distinct from an **idle** connection being closed, which is silent and carries no `408`: see [Connections](#connections). A client that receives `408` may retry the request on a new connection.

    Like the `400`, `411` and `413` beside it, the body is JSON labelled `text/html; charset=utf-8`.

!!! note "Mirror servers are read-only"
    A Password Depot server that runs as a mirror of another server accepts only `GET` on authenticated routes. Every other request that carries a bearer token - `POST`, `PUT`, `PATCH`, `DELETE`, including `POST /auth/logout` - answers `403 Forbidden` with `error.code` `403` ("The mirror server does not support this operation.", localized), before the token itself is examined. `POST /auth/login` and the other routes that need no token are not affected. Send writes to the primary server. The `icons.can_upload` flag of a [database](databases.md#icons-capability) is `false` on a mirror.

---

## Connections

*Server 20.0.0 and later.* The server keeps an HTTP/1.1 connection open between requests. Earlier servers closed the connection after every response, so every call paid a TCP handshake and a TLS handshake; a client that reuses connections now pays them once. No client change is required: browsers, OkHttp, .NET `HttpClient` and `Invoke-RestMethod` all reuse connections by default.

**What the server does**

- Persistent connections are on by default. `Connection: close` in a request is honoured, and an HTTP/1.0 request without `Connection: keep-alive` is answered and closed, exactly as before.
- Every response that keeps the connection carries `Keep-Alive: timeout=13`. It is advisory; it describes the hop the client is talking to, which behind a proxy is the proxy and not this server.
- **An idle connection is closed silently after 15 seconds.** There is no `408` and no response of any kind - the connection simply ends. A client must be prepared to open a new one, and should **retry an idempotent request once** if it fails on a connection it took from a pool. The timeout is configurable by the administrator (`RESTKeepAliveTimeout` in `pdserver.ini`).
- A request that has started but stops arriving mid-way is answered [`408`](#http-status-codes) after 30 seconds (`RESTRequestReadTimeout`) and the connection is closed.
- **After 1000 requests** on one connection the server asks for a new one: that response carries `Connection: close`. Continue on a fresh connection.
- At most **1024 REST connections** are served at a time (`RESTMaxConnections`). Above 75 % of that number the server stops granting keep-alive - responses carry `Connection: close` - so that idle connections drain. Above the cap itself a new connection is refused at TCP level, **before** the TLS handshake and with no HTTP answer, which a client cannot distinguish from the server being down. Earlier servers had no cap.
- **Which answers close the connection:** a `408`, a `400` for a duplicate `Content-Length`, a header-stage `411` or `413`, any request refused before its body was read, the 1000-request limit, the soft connection limit, and a client's own `Connection: close`. A `404` does **not** close the connection any more; on Server 19.x it did.
- **Send no bytes between requests.** A stray blank line before a request line - which [RFC 7230 &sect;3.5](https://datatracker.ietf.org/doc/html/rfc7230#section-3.5) says a server *should* tolerate - makes this server drop the connection without an answer.
- The administrator can restore the previous behaviour with `RESTKeepAlive=0` in `pdserver.ini`. The file is read when the service starts, so that means: stop the service, change the setting, start the service again.

**Windows PowerShell 5.1.** `Invoke-WebRequest` and `Invoke-RestMethod` reuse connections and their idle timeout is well above the server's, so the server is always the side that closes. A `POST` or `PUT` issued just as a 15-second-idle connection is being closed can fail with *"The underlying connection was closed: A connection that was expected to be kept alive was closed by the server."* Scripts that sleep between calls are the ones at risk; add `-DisableKeepAlive` to those calls, or retry once. PowerShell 7 retries such a failure itself.

**Reverse proxies.** A proxy that forwards with HTTP/1.0 and `Connection: close` upstream (the nginx default) is unaffected. If upstream keep-alive is enabled (`proxy_http_version 1.1` plus `keepalive`, IIS ARR, HAProxy), set the proxy's upstream idle timeout **below** `RESTKeepAliveTimeout`, or raise `RESTKeepAliveTimeout` above the proxy's (nginx defaults to 60 seconds), so that the proxy rather than the server is the closing side; otherwise a non-idempotent request that races the server's close surfaces as a `502`, which nginx does not retry. Such a proxy also multiplexes different users over one upstream connection; every request is authenticated and audited on its own, but **Windows integrated sign-in (Negotiate/NTLM) through a connection-sharing proxy is not supported** - multi-leg SPNEGO needs the legs of one handshake to stay on one connection.

**Protocol notes for strict intermediaries.** A `204 No Content` is sent with `Content-Length: 0`, which [RFC 7230 &sect;3.3.2](https://datatracker.ietf.org/doc/html/rfc7230#section-3.3.2) says a server should omit; the value is unambiguous and no client can mis-frame on it. The `Keep-Alive` header is not named in the `Connection` header, as it is with Apache. A compound `Connection: close, TE` is not recognised as a close request - the server keeps the connection, the client closes it, and nothing is mis-framed. Every response is framed by `Content-Length`; the server never sends a chunked response, a `Transfer-Encoding`, a `304` or a byte range.

---

## Client vs Admin Scope

The v2.0 API separates endpoints into **client** and **admin** scopes:

- **Client scope** (`"scope": "client"`, the default) -- Access to databases (read-only), folders, entries, search, and the user/group directory (read-only, compact representation). Client sessions see only databases the user has permissions on.
- **Admin scope** (`"scope": "admin"`) -- All client endpoints, plus management endpoints under `/admin/` for database CRUD, user/group CRUD, permissions, alerts, and secrets. Admin sessions see all server databases.

The scope is set at login time via the `scope` field in the request body. See [Authentication](authentication.md#client-vs-admin-scope) for details.

## Endpoint Summary

All paths below are relative to the base URL (`/v2.0/`).

### Auth

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `POST` | [`/auth/login`](authentication.md#login) | Authenticate and obtain access token | -- |
| `POST` | [`/auth/logout`](authentication.md#logout) | End session, invalidate token | Any |
| `GET` | [`/auth/oidc`](authentication.md#oidc-providers) | List configured OIDC/Azure identity providers | -- |
| `POST` | [`/auth/webauthn/begin`](authentication.md#webauthn) | Begin WebAuthn/Passkey authentication | -- |
| `POST` | [`/auth/webauthn/complete`](authentication.md#webauthn) | Complete WebAuthn/Passkey authentication | -- |

### User Profile

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/me`](users.md#user-profile) | Get current user's profile (includes passkeys) | Any |
| `POST` | [`/me/password`](users.md#change-own-password) | Change own password | Any |
| `GET` | [`/me/passkeys`](users.md#list-own-passkeys) | List own passkeys | Any |
| `POST` | [`/me/passkeys/begin`](users.md#register-passkey-begin) | Begin passkey registration | Any |
| `POST` | [`/me/passkeys/complete`](users.md#register-passkey-complete) | Complete passkey registration | Any |
| `PATCH` | [`/me/passkeys/{id}`](users.md#rename-passkey) | Rename own passkey | Any |
| `DELETE` | [`/me/passkeys/{id}`](users.md#delete-own-passkey) | Delete own passkey | Any |

### Databases (Client)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases`](databases.md#list-databases) | List accessible databases | Any |
| `GET` | [`/databases/{id}`](databases.md#get-database) | Get database details | Any |
| `GET` | [`/databases/{db}/categories`](databases.md#list-categories) | List the category names the database carries | Any |

### Navigation (Children)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases/{db}/children`](folders.md#root-level-children) | List root-level folders and entries | Any |
| `GET` | [`/databases/{db}/folders/{id}/children`](folders.md#folder-children) | List children of a folder | Any |

### Folders

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `POST` | [`/databases/{db}/folders`](folders.md#create-folder) | Create a new folder | Any |
| `GET` | [`/databases/{db}/folders/{id}`](folders.md#get-folder) | Get folder details | Any |
| `PATCH` | [`/databases/{db}/folders/{id}`](folders.md#update-folder) | Update a folder | Any |
| `DELETE` | [`/databases/{db}/folders/{id}`](folders.md#delete-folder) | Delete a folder: to the recycle bin, or `?mode=permanent` | Any |
| `POST` | [`/databases/{db}/folders/{id}/move`](folders.md#move-folder) | Move a folder to a different parent | Any |

### Entries

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `POST` | [`/databases/{db}/entries`](entries.md#create-entry) | Create a new entry | Any |
| `GET` | [`/databases/{db}/entries/{id}`](entries.md#get-entry) | Get full entry details (including password) | Any |
| `PATCH` | [`/databases/{db}/entries/{id}`](entries.md#update-entry) | Update an entry | Any |
| `DELETE` | [`/databases/{db}/entries/{id}`](entries.md#delete-entry) | Delete an entry: to the recycle bin, or `?mode=permanent` | Any |
| `POST` | [`/databases/{db}/entries/{id}/move`](entries.md#move-entry) | Move an entry to a different folder | Any |
| `GET` | [`/databases/{db}/entries/{id}/otp`](entries.md#get-one-time-code) | Get the entry's current one-time code (TOTP) | Any |
| `GET` | [`/databases/{db}/entries/{id}/content`](entries.md#get-document-content) | Download document or certificate content (BLOB) | Any |
| `PUT` | [`/databases/{db}/entries/{id}/content`](entries.md#upload-document-content) | Upload/replace document or certificate content (BLOB) | Any |

### Recycle Bin

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases/{db}/recyclebin`](recyclebin.md#list-recycle-bin) | List the deleted items you may see | Any |
| `POST` | [`/databases/{db}/recyclebin/{id}/restore`](recyclebin.md#restore-item) | Put one item back where it was deleted from | Any |
| `DELETE` | [`/databases/{db}/recyclebin/{id}`](recyclebin.md#delete-item) | Destroy one item permanently | Any |
| `DELETE` | [`/databases/{db}/recyclebin`](recyclebin.md#empty-recycle-bin) | Destroy what you can see in the bin and may delete | Any |

### Database Icons

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases/{db}/icons`](icons.md#list-icons) | List a database's icons, or fetch several images in one call | Any |
| `GET` | [`/databases/{db}/icons/{icon_id}`](icons.md#get-icon) | Get one icon with its image | Any |
| `POST` | [`/databases/{db}/icons`](icons.md#upload-icon) | Upload a new icon (PNG, Base64 in JSON) | Any |

### Search

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | `/databases/{db}/search` | Search entries within a database | Any |

### Users (Client)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/users`](users.md#list-users) | List all users (compact) | Any |
| `GET` | [`/users/{id}`](users.md#get-user) | Get user details (compact) | Any |

### Groups (Client)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/groups`](groups.md#list-groups) | List all groups (compact) | Any |
| `GET` | [`/groups/{id}`](groups.md#get-group) | Get group details (compact) | Any |

### Databases (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/databases`](databases.md#list-all-databases-admin) | List all server databases | Admin |
| `POST` | [`/admin/databases`](databases.md#create-database-admin) | Create a new database | Admin |
| `GET` | [`/admin/databases/{id}`](databases.md#get-database-admin) | Get database details | Admin |
| `PATCH` | [`/admin/databases/{id}`](databases.md#update-database-admin) | Update database settings | Admin |
| `DELETE` | [`/admin/databases/{id}`](databases.md#delete-database-admin) | Delete a database | Admin |

### Permissions (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/databases/{db}/permissions`](permissions.md#list-permissions) | List permissions for a database | Admin |
| `POST` | [`/admin/databases/{db}/permissions`](permissions.md#create-permission) | Create a permission rule | Admin |
| `GET` | [`/admin/databases/{db}/permissions/{id}`](permissions.md#get-permission) | Get permission rule details | Admin |
| `PATCH` | [`/admin/databases/{db}/permissions/{id}`](permissions.md#update-permission) | Update a permission rule | Admin |
| `DELETE` | [`/admin/databases/{db}/permissions/{id}`](permissions.md#delete-permission) | Delete a permission rule | Admin |

### Users (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/users`](users.md#list-users-admin) | List all users | Admin |
| `POST` | [`/admin/users`](users.md#create-user-admin) | Create a new user | Admin |
| `GET` | [`/admin/users/{id}`](users.md#get-user-admin) | Get user details | Admin |
| `PATCH` | [`/admin/users/{id}`](users.md#update-user-admin) | Update a user | Admin |
| `DELETE` | [`/admin/users/{id}`](users.md#delete-user-admin) | Delete a user | Admin |
| `POST` | [`/admin/users/{id}/password`](users.md#change-password-admin) | Change a user's password | Admin |
| `GET` | [`/admin/users/{id}/passkeys`](users.md#admin-list-any-users-passkeys) | List any user's passkeys | Admin |
| `DELETE` | [`/admin/users/{id}/passkeys/{pid}`](users.md#admin-revoke-any-users-passkey) | Revoke any user's passkey | Admin |

### Groups (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/groups`](groups.md#list-groups-admin) | List all groups | Admin |
| `POST` | [`/admin/groups`](groups.md#create-group-admin) | Create a new group | Admin |
| `GET` | [`/admin/groups/{id}`](groups.md#get-group-admin) | Get group details | Admin |
| `PATCH` | [`/admin/groups/{id}`](groups.md#update-group-admin) | Update a group | Admin |
| `DELETE` | [`/admin/groups/{id}`](groups.md#delete-group-admin) | Delete a group | Admin |

### Alerts (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/alerts`](alerts.md#list-alerts) | List all alerts | Admin |
| `POST` | [`/admin/alerts`](alerts.md#create-alert) | Create a new alert | Admin |
| `GET` | [`/admin/alerts/{id}`](alerts.md#get-alert) | Get alert details | Admin |
| `PATCH` | [`/admin/alerts/{id}`](alerts.md#update-alert) | Update an alert | Admin |
| `DELETE` | [`/admin/alerts/{id}`](alerts.md#delete-alert) | Delete an alert | Admin |

### Secrets

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/secrets`](secrets.md#list-secrets) | List own secrets | Any |
| `POST` | [`/secrets`](secrets.md#create-secret) | Create a shared secret | Any |
| `GET` | [`/secrets/{id}`](secrets.md#get-secret) | Get own secret details | Any |
| `DELETE` | [`/secrets/{id}`](secrets.md#delete-secret) | Delete own secret | Any |
| `POST` | [`/secrets/{id}/approve`](secrets.md#approve-secret) | Approve a secret | Any |
| `POST` | [`/secrets/{id}/reject`](secrets.md#reject-secret) | Reject a secret | Any |
| `POST` | [`/secrets/{id}/revoke`](secrets.md#revoke-secret) | Revoke a secret | Any |
| `GET` | [`/admin/secrets`](secrets.md#list-secrets) | List all secrets | Admin |
| `POST` | [`/admin/secrets`](secrets.md#create-secret) | Create a shared secret | Admin |
| `GET` | [`/admin/secrets/{id}`](secrets.md#get-secret) | Get any secret details | Admin |
| `PATCH` | [`/admin/secrets/{id}`](secrets.md#update-secret-admin) | Update a secret | Admin |
| `DELETE` | [`/admin/secrets/{id}`](secrets.md#delete-secret) | Delete any secret | Admin |

---

## Data Conventions

### Booleans

Boolean fields use native JSON booleans:

```json
{
  "disabled": true,
  "ad_sync": false
}
```

!!! note "Difference from v1.0"
    v1.0 encoded booleans as strings (`"1"` / `"0"`). v2.0 uses native `true` / `false`.

### Dates

Dates are returned in **ISO 8601** format:

```json
{
  "updated_at": "2024-06-01T08:00:00.000Z",
  "expires_at": "2025-06-01T00:00:00.000Z"
}
```

All entity timestamp fields are genuine UTC instants with the trailing `Z`, and inbound timestamp fields are interpreted as UTC.

A `null` value indicates the field is not set.

### Resource Identifiers

All resources use UUID-style string identifiers:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000"
}
```

The one exception is a [database icon](icons.md#icon-object): its `id` is a short string of decimal digits that is valid only inside its database, and the icon's `name` is its identifier.

### Permissions

v2.0 responses do not carry a permission string. Database, folder and entry representations have no `rights` field - that was part of REST API v1.0. A request you lack the permission for answers `403`.

Where permissions appear as data - in the permission rules under [`/admin/databases/{db}/permissions`](permissions.md) - they are JSON arrays of tokens such as `"read"`, `"update"` or `"share"`; see [Rights Values](permissions.md#rights-values).
