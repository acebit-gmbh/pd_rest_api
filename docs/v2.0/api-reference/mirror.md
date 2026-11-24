# Mirror Servers

!!! note "Server 20.0.0 and later"
    This page describes Server 20.0.0 and later. A mirror server of an earlier version serves every `GET` and the sign-in and answers every other request that carries a bearer token with `403`, as the [overview](overview.md#http-status-codes) says. What changed is listed under [Mirror Servers](../changelog.md#mirror-servers-behavior-change) in the changelog.

A mirror server is a second Password Depot server that keeps a copy of the databases and the configuration of its **primary server** and brings that copy up to date from it. Users sign in on a mirror server and read their databases there, also while the primary server cannot be reached; every change is made on the primary server. An administrator can let the mirror take over as the primary server: in a planned switch-over the primary server hands over to its mirror, and in a fail-over the mirror takes over from a primary server that no longer answers and tells that server to stop once it reaches it again. A former primary server that has handed over, or has been told to stop, refuses every client and, where it knows its address, says which server took its place.

This page says what a REST client meets on a mirror server, on a server that hands over, and after a mirror has taken over. The administrator sets a mirror up and runs a switch-over or a fail-over in the Server Manager, on its *Mirroring* page.

| Where | What a client meets |
|-------|---------------------|
| [On a mirror server](#what-a-mirror-server-serves) | Reads are served; a change is refused with `403` |
| [Signing in on a mirror](#signing-in-on-a-mirror-server) | Signing in works; a token of another server is answered `401` |
| [A mirror that leaves its primary server](#a-mirror-that-leaves-its-primary-server) | Every request is refused with `403` until its service is restarted |
| [A server that hands over](#a-server-that-hands-over-or-has-been-replaced) | Every request is refused with `403` and a text that says so; a server that has been replaced names the new primary server where it knows its address |
| [After a mirror has taken over](#after-a-mirror-has-taken-over) | The new primary server serves every request; sign in again and issue long-lived API tokens anew |

Every refusal on this page uses the published [error object](overview.md#error-format) with `error.code` equal to the HTTP status. Match the status, never the message: the message is a text for people, to be shown as it is.

---

## What a Mirror Server Serves

A mirror server answers from its copy. It takes no change from a client:

| Request | On a mirror server |
|---------|--------------------|
| Every `GET` | Served from the mirror's copy, as on the primary server |
| `POST /auth/login`, `POST /auth/webauthn/begin` and `POST /auth/webauthn/complete` | Served: a sign-in on the mirror (see [Signing In on a Mirror Server](#signing-in-on-a-mirror-server)) |
| `POST /auth/logout` | Served |
| The routes of the [client channel](channel.md) | Served; each answers on a mirror as [the client channel](#the-client-channel-on-a-mirror-server) says below |
| Every other request that carries a bearer token -- `POST`, `PUT`, `PATCH` and `DELETE` | `403 Forbidden` with `error.code` `403` and the message "The mirror server does not support this operation." (localized), before the token is examined. Nothing is changed |

```json
{
  "error": {
    "code": 403,
    "message": "The mirror server does not support this operation."
  }
}
```

- A request without a bearer token is answered `401`, as on every server.
- A route of the client channel is recognised in its documented form, with or without a trailing slash. Another form of it -- another letter case, an extra segment -- is refused with the `403` above.
- The `icons.can_upload` flag of a [database](databases.md#icons-capability) is `false` on a mirror server.
- Send every change to the primary server. A client that cannot reach it keeps the user's unsaved input and tells the user that the server takes no changes at the moment.

**Databases on a mirror server.** While the mirror brings its copy of a database up to date from the primary server, and whenever it cannot serve its copy, every route under `/v2.0/databases/{db_id}` but those of the client channel answers `503 Service Unavailable` with `error.code` `503` and the message "This database is not available at the moment. Try again later.", as for every [database that is not available at the moment](databases.md#databases-not-available-at-the-moment); the client channel answers `503` with a word (below). Try again later: nothing is lost.

**Shared links on a mirror server.** The HTTPS page of a [shared link](secrets.md#access-urls) opens nothing on a mirror server. It says "This link can be opened on the primary server *address* only.", or "This link can be opened on the primary server only." where the mirror's settings name no address. Open the link on the primary server.

### The Client Channel on a Mirror Server

An app that syncs a database through the [client channel](channel.md) keeps syncing on a mirror server, read-only:

- **Open a database.** The answer carries `writable` `false` and the member `mirror`: `principal`, the primary server's address for clients as the mirror's settings name it (`null` where they name none), and `as_of`, the time in milliseconds since 1970-01-01 UTC at which the mirror last knew its copy of the database to equal the primary server's. It carries no `offline`, `server`, `top` or `shared_secrets`, and its `blobs` holds `push` `false` and no `icons`. See [Open a Database](channel.md#open-a-database).
- **Pull, manifest, fetch, history and download chunks** are served from the copy.
- **Push.** Every batch is answered `deferred` with the reason `read-only`: nothing is applied, and the changes stay pending until the app reaches a server that takes them.
- **Editing hint.** `403` with the word `read only mirror` and `error.principal`, the address `mirror.principal` names.
- **Upload a chunk.** `503` with the word `not served`; nothing is stored. A chunk that is not of its form is refused as on every server.
- **Offline copies.** [Ask for a Lease](channel.md#ask-for-a-lease) and [Report What Was Done in a Copy](channel.md#report-what-was-done-in-a-copy) answer `503` with the word `renew at the principal`, and nothing is recorded: the copy is kept, and renews its lease and sends its report at the primary server.
- **A copy that is being brought up to date.** Every request for the database answers `503` with the word `busy` and `error.retry_after` while the mirror brings its copy up to date or waits for the primary server's configuration of it; `not served` where the mirror holds no copy of the database that it can serve now. Both are waits: the app keeps its tab, its pending changes and any offline copy, backs off and tries again.

---

## Signing In on a Mirror Server

Users sign in on a mirror server with their accounts, as on the primary server, and receive a session token that the mirror issued. The mirror refuses a sign-in -- `POST /auth/login` and both steps of a passkey sign-in -- with `403` and `error.code` `403`, before any credential is examined and without counting it towards the IP lockout, where:

- it is no longer a mirror of its primary server, because the primary server ended the pairing or the server it reaches there is no longer the one it was paired with: "This server is no longer a mirror of its primary server. Sign in on the primary server.";
- its administrator set the mirror's maximum age for sign-ins (the Server Manager's *Mirror settings*, off by default) and no database on it has been brought up to date from the primary server for longer than that: "This mirror has not been brought up to date from its primary server for more than *n* hours. Sign in on the primary server." (with "for more than an hour" where *n* is 1)

Sign in on the primary server instead.

### Tokens on a Mirror Server

A token works on the server that issued it:

| Token sent to a mirror server | Answer |
|-------------------------------|--------|
| A session token the mirror issued | Accepted, as on every server |
| A long-lived API token, or a session token of the primary server where the user also holds a REST session on the mirror | `401` with `error.code` `401` and the message "This server is a mirror of *address*. Sign in here again; API tokens work on the primary server only." -- "This server is a mirror. Sign in here again; API tokens work on the primary server only." where the mirror's settings name no address of the primary server |
| A session token of the primary server where the user holds no REST session on the mirror | `401` with "Access token is invalid or expired.", as on every server |

Either `401` means: sign in again, on the mirror or on the primary server. **Long-lived API tokens work on the primary server only:** they are created in the Server Manager of the primary server, a mirror server creates none, and a script that uses one sends its requests to the primary server.

---

## A Mirror That Leaves Its Primary Server

An administrator can let a mirror server leave its primary server; the Leave finishes when the mirror's service is restarted. From the Leave until that restart, the mirror answers every request -- a `GET`, a sign-in, a shared link and a file included -- with `403` and the message "This server has left its primary server. Restart the service to finish." Where the Leave stopped before it finished, the message is "This server stopped serving, but leaving its primary server did not finish. Choose Leave the primary server... again to finish." until the administrator runs the Leave again. Connect to the primary server.

---

## A Server That Hands Over or Has Been Replaced

A primary server that hands over to its mirror in a switch-over, and one that has been replaced by another primary server, answer every request with `403` and `error.code` `403` before the token is examined: a `GET`, every step of a sign-in, a shared link and a file included.

| The server | Its message |
|------------|-------------|
| Hands over to its mirror | "This server is handing over to its mirror. Connect to the new primary server when the handover is complete." |
| Has been replaced, and knows the new primary server's address | "This server has been replaced by the primary server *address*. Connect to that server." |
| Has been replaced, and knows no address | "This server has been replaced by another primary server." |

An app stops sending to the server, shows its text, keeps its pending changes and any offline copy, and connects to the new primary server when the user chooses it. It sends no retry of its own: the server takes requests again only once its administrator resumes it as the primary server.

**Browser applications.** The refusal also answers a browser's CORS preflight (`OPTIONS`), so a browser reports a request that needs a preflight -- one that carries a bearer token or a JSON body -- as a network error, and the text does not reach the application. A request that needs no preflight, such as [`GET /auth/oidc`](authentication.md#oidc-providers) with no token, carries the refusal and its text.

While a mirror is taking over, it takes no change: every request other than a `GET` that carries a bearer token is answered with the mirror's `403` above.

---

## After a Mirror Has Taken Over

Once a mirror has taken over, it is the primary server: it serves every request, and its databases take changes.

- **Sign in again.** Session tokens of the former primary server are answered `401` with "Access token is invalid or expired.".
- **Issue long-lived API tokens anew.** Long-lived API tokens of the former primary server do not work on the new one: they are answered `401` with "Access token is invalid or expired.". An administrator creates new ones in the Server Manager of the new primary server, whose dashboard reminds the administrator of this for 30 days after the takeover.
- **Each database has a new store.** An app of the client channel finds another `incarnation` and reconciles, as after a database was restored. A change it had pushed to the former primary server and sends again is not applied twice.
- **Offline copies** renew their lease at the new primary server, which issues a new one.
- **The policy bundle.** The new primary server keeps the server's id in `server` and answers a new `incarnation` (see [Policies for Clients](client-policy.md)).
