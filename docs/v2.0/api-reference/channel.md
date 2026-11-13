# Client Channel

*Server 20.0.0 and later.*

The client channel is the sync connection of the Password Depot apps. An app that keeps a server database open opens it for sync, receives the database's records and their changes in pulls, sends its own changes in pushes of whole batches, reads a record's history on demand and moves a document's content in chunks. The channel's routes lie under `/v2.0/databases/{db}/`, beside the per-object routes, and use the same sign-in, the same bearer token and the same error object, which gains the member `word`.

The per-object routes (folders, entries, search and the others) stay as they are for every caller. An app that syncs a database through the channel changes its contents by pushes alone: a change made through a per-object route bypasses the app's pending changes and comes back to the app as another client's change.

| Where | What |
|-------|------|
| [`POST /v2.0/auth/login`](authentication.md#client-protocol) and [`POST /v2.0/auth/webauthn/begin`](authentication.md#client-protocol) | The sign-in that declares the protocol the app speaks, `client.protocol` |
| [`POST /v2.0/databases/{db}/session`](#open-a-database) | Open a database for sync, or close it |
| [`GET /v2.0/databases/{db}/sync`](#pull-changes) | Pull the database's records and their changes |
| [`POST /v2.0/databases/{db}/sync`](#push-changes) | Push changes, in batches |
| [`GET /v2.0/databases/{db}/manifest`](#read-the-manifest) | Every record the user may see, with its version, for a reconcile |
| [`POST /v2.0/databases/{db}/sync/fetch`](#fetch-records) | Records by id |
| [`POST /v2.0/databases/{db}/entries/{id}/editing`](#editing-hint) | Tell other users that the user is editing an entry |
| [`GET /v2.0/databases/{db}/entries/{id}/history`](#history), and the same under `folders` | A record's history, as a list |
| [`GET /v2.0/databases/{db}/entries/{id}/history/{item}`](#history) and [`POST /v2.0/databases/{db}/entries/{id}/history`](#history), and the same under `folders` | Old versions of a record, with their values |
| [`PUT /v2.0/databases/{db}/blobs/{blob}`](#upload-a-chunk) | Upload one chunk of a document's content |
| [`GET /v2.0/databases/{db}/blobs/{blob}`](#download-chunks) | Download the chunks of a document's content |
| [`GET /v2.0/databases`](databases.md#list-databases) | The databases the user may open: the channel uses the published list |

!!! note "Records"
    The records the channel carries -- a record's `body`, its `vv` and `level`, the units of a push -- and the sealed values inside them are written in the Password Depot record format, which this reference does not describe. This page describes the requests, the answers around the records, the errors and the bounds. Parse every answer as JSON and ignore members you do not know; a record's `body` is the exception, see [Push Changes](#push-changes).

---

## Signing In for the Channel

An app declares the protocol it speaks when it signs in: the integer `client.protocol` in the `client` object of `POST /auth/login`, or of `POST /auth/webauthn/begin` for a passkey sign-in. This server speaks protocol `2`. The sign-in's last answer then carries `client_protocol` and the account's `id`:

```json
{
  "user": "alice",
  "pass": "<the account's password>",
  "client": {"platform": "ios", "version": "20.0.0", "protocol": 2}
}
```

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "id": "A11CE000-0000-4000-8000-000000000001",
  "client_protocol": 2,
  "policy": {"type": "pd-policy-bundle", "...": "..."}
}
```

- `access_token` is sent as `Authorization: Bearer <token>` on every channel request, as on every other route. It stays good while the REST session lives (see [Token Lifetime](authentication.md#token-lifetime)). A `401` ends it: the app signs in again and opens its databases again.
- `id` is the account's id as the server holds it, letter case included. `GET /me` answers the same text as `id`.
- `client_protocol` is the protocol the server admitted. A sign-in answer without it comes from a server that serves no channel: the app sends no channel request there.
- A number this server does not speak answers `403` with `error.code` `4039`, the word `protocol not supported` and the numbers it speaks in `error.protocol`. A value that is not a JSON integer from 1 to 65535 answers `400` with the word `malformed`. See [Client Protocol](authentication.md#client-protocol) for the two-step sign-ins, the error bodies and the rules.

A session of the `admin` scope is answered `403` with the word `not permitted` on every channel route, whether its sign-in declared a protocol or not: the channel serves client-scope sessions. Any other session that declared no protocol -- a sign-in without `client.protocol`, and every long-lived API token of the client scope -- is answered `403` with `error.code` `4039` and the word `protocol required` on every channel route; every other route works for it as before.

---

## The Channel in a REST Session

### One State per REST Session

Each REST session holds a channel state of its own: the databases it opened for sync, each with its field key, its `writer` id and the state of a pull or reconcile in progress, its editing hints and its rate bounds. Nothing of it carries over to the user's other REST sessions or to a connection of the same user from the Windows client, so each REST session opens its databases itself, under its own field key, and a `next` of one REST session means nothing to another.

The state lives in the server's memory and ends with the REST session: at its logout, at a change of the account's password (the session that changes its own keeps its state, the account's other sessions lose theirs), at a disconnect of the user in the Server Manager, when the session expires or is ended by a newer sign-in beyond the limit of [Sessions](authentication.md#sessions), when the account is disabled or deleted, and when the server stops. A restart of the server ends every REST session: the app signs in and opens its databases again. Nothing is resumed; the app goes on from its stored cursor.

The cursor a pull answers holds on later REST sessions of the same user too: after a new sign-in the app opens the database again with the same `writer` id and pulls since its cursor.

### One Request at a Time

The server serves the channel requests of one REST session one after the other. Two pulls sent at once are served in turn, and the second drops the first one's parts (see [Pull Changes](#pull-changes)). HTTP gives no order: an app that needs one waits for the answer before it sends the next request.

- A request waits for its turn at most 10 seconds; then it is answered `503` with the word `busy`, and nothing of it was done.
- At most 4 requests of a REST session wait beside the one being served; one more is answered at once `429` with the word `rate limited`, `Retry-After: 1` and `error.retry_after` `1`.

### A Lost Answer

On a mobile network an answer that never arrives is the usual failure. The app does not know whether the server served the request, and the server may still be serving it. Wait at least 40 seconds for an answer: a request can wait 10 seconds for its turn before the server works on it. A shorter wait loses nothing and costs a repeat, which takes its turn behind the first request. Then, by request:

| Request | What the app does after a lost answer |
|---------|---------------------------------------|
| Push | Push the same changes again. The server answers a batch it already applied from its receipts and writes nothing again |
| Pull and manifest | A `next` is good once: the lost answer moved the pull on, so the same `next` answers `409` with the word `part expired`. A pull since a cursor starts again since the stored cursor, and a reconcile starts again from its first part. A first pull of which the app stored parts goes on by reconcile, never by a new first pull: a first pull names no records that are gone |
| Open a database | Send it again with the same field key and `writer` id. Open a database again only after the word `no session` or a new sign-in, never for another lost answer: opening it again ends a running pull's parts |
| Upload a chunk | Send the chunks the newest `held` did not list |
| Fetch, history, download chunks, editing hint | Send it again |

### No Notifications: Poll

The server sends nothing that the app did not ask for. Over REST no message tells the app that the database changed, that another user started editing an entry, or that the session ended: the next request's answer does -- `401` where the REST session is over, `503` with the word `busy` or no answer at all where the server stops.

The app learns of a change by pulling:

- since its stored cursor about every 60 seconds while a database is open and the app is in the foreground, with a random part added so that apps do not poll together;
- at once when the app returns to the foreground;
- when the instant `access_next` of the last completed pull has passed.

At most one pull is in flight per database, and a pull in parts counts as one until its completing part: never start a new pull between two parts, since it drops the running one's parts. A change of the user's permissions writes no change into the database, so the poll is also how a changed permission reaches the app, by `access_gen`.

Every request counts as activity for the server's **Disconnect after inactivity** policy, as every request of a REST session does (see [Token Lifetime](authentication.md#token-lifetime)). An app that polls on keeps its session: it stops polling when it locks, and when its user has been away for the app's own lock time, and goes on when the user returns.

### What an App Keeps

An app keeps what it receives through the channel -- the cursor, the records, the field key and its pending changes -- in memory only: nothing of it outlives the app's process, and the next launch starts with a first pull. The field key is never logged and never written to a disk.

---

## The Database Gate

Every channel request names a database by the `{db}` of its path: the database's id as [`GET /databases`](databases.md#list-databases) answers it, in either letter case. The server admits the request where the database exists and the user holds the use permission on the database itself -- the same permission by which `GET /databases` lists a database and the per-object routes open it. Otherwise it answers `404` with the word `not found`, the same answer for every cause, and closes that database in the REST session. Where the server cannot serve the database at the moment, it answers `503` with the word `not served` and the database stays open: back off. A disabled or deleted account is answered `401`, never `404` (see [A Status with No Word](#a-status-with-no-word)).

A database on which the user holds the use permission appears in the user's database list and opens, also where nothing inside it is permitted to the user. It opens empty: [Open a Database](#open-a-database) answers as for every user the gate admits; a pull and the manifest deliver no folder and no entry; a fetch answers the id of every folder and entry in `missing`; history answers every record as one the user may not read; a create in a push is rejected `not authorised`; an upload is refused `not authorised`. A permission granted inside later reaches the app with its next pull or reconcile.

**Access lost while a database is open.** A user whose last permission inside the database ends keeps the database open: the next pull shows a changed `access_gen`, the app reconciles, the records the user no longer sees leave, and the database stays open, empty. Losing access to the database itself -- the use permission on the database, or the database -- answers `404` with the word `not found` to the app's next request for the database. The app then opens the database again after 1, 2 and 4 seconds; where these three attempts in a row answer `not found`, the access is lost. One that succeeds ends the check, and the app goes on as before. Once the access is lost, the app sends nothing more for that database and tells the user that the database is no longer available, with one text for every cause, and what is lost: the changes it could not send. The user confirms, and the app closes the database and wipes what it held of it.

---

## Open a Database

```
POST /v2.0/databases/{db}/session
```

Opens the database `{db}` for sync in this REST session, or opens it again with a new field key or `writer` id. Every other channel request but the [editing hint](#editing-hint) needs the database opened so; without it they answer `409` with the word `no session`.

### Request Body

`Content-Type: application/json`, at most 4096 bytes.

```json
{
  "writer": "a1b2c3d4e5f60718",
  "field_key_epoch": 1,
  "field_key": "<43 characters of base64url>"
}
```

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `writer` | string | Yes | An id the app draws for this opening of the database: 8 random bytes as 16 lower-case hexadecimal digits. The changes the app pushes are counted under it. Keep it, with its count, across reconnects and a new sign-in of the same user while the app holds the database; draw a new one each time the app opens the database anew. An id first used by another user on this database answers `409` with the word `writer of another principal`: draw a new one and open the database again |
| `field_key_epoch` | integer | Yes | `1` |
| `field_key` | string | Yes | The field key: 32 random bytes the app draws for its copy of the database, as base64url without padding -- exactly 43 characters, the two spare bits of the last one zero. Values the user may read arrive sealed under it. Verify the server's certificate before you send it, keep it in memory only, and never log it |
| `notify` | boolean | No | Accepted, with no effect over REST: nothing is notified (see [No Notifications](#no-notifications-poll)) |

Send `field_key` once, as a member of the body's object, and write no `\u` escape anywhere in the body: the server reads the key exactly as sent. Either fault answers `400` with the word `malformed`, as does a body above 4096 bytes, a required field that is missing, a field not of its form, a `field_key_epoch` other than `1`, and one of these fields or `end` given twice; a member the route does not know is ignored. The server keeps the key in memory only and clears the request body when the request ends, whatever it answered.

### Response

`200 OK`:

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 1234,
  "writable": true,
  "db_id": "3f2a9c1e-5b7d-4e8f-a012-3456789abcde",
  "root": "9b0e4d6a-2c1f-4e3b-8a5d-7f6e5d4c3b2a",
  "floor": 36,
  "recycle_bin": {"max_items": 1000, "manage": false},
  "usage": {
    "usage.attachments.external_open": true,
    "usage.autofill.channels": ["auto_type", "browser", "internal_browser", "mobile_autofill"],
    "usage.clipboard.allowed": true,
    "usage.export.channels": ["copy_to_database", "file", "save_as", "sync"],
    "usage.print.allowed": true
  },
  "blobs": {"max_size": 67108864, "push": true},
  "audit": {"audit.log_secret_access": true, "audit.reason.delete": false},
  "release_secret": null
}
```

The example is indented for reading; the server writes the answer compactly, in the order shown.

| Field | Type | Description |
|-------|------|-------------|
| `incarnation` | string | The id of the database's current store, 16 bytes in base64url. A pull answer with another `incarnation` means that the app reconciles |
| `generation` | integer | The database's change number: it rises with every change written to the database |
| `writable` | boolean | `false` where the database takes no changes at the moment. It is still pulled; a push's batches are then deferred `read-only` |
| `db_id` | string | The database's own id, in lower case. Compare it with the `{db}` you opened before the first pull; where they differ, open nothing |
| `root` | string | The id of the database's root record: every top-level folder and entry names it as its parent, also where the user sees no record yet |
| `floor` | integer | The floor the server holds for this `writer` id, as a push answer names it (see [Push Changes](#push-changes)); absent where the server holds nothing for that id yet. For diagnostics only |
| `recycle_bin` | object | The recycle bin as it applies to the user: `max_items`, the number of top-level items the bin keeps, `0` to `10000` (`0`: a deletion does not stay in the bin, so delete as "delete permanently" does); `manage`, `true` where the user manages this database's bin and may reach every item in it, `false` where only the items the user deleted. Either way the user's permissions on an item's place decide too. An app that receives no `recycle_bin` offers no command of the bin |
| `usage` | object | The usage policies as they apply to the user on this database, by setting id: `usage.autofill.channels` and `usage.export.channels` as arrays of words, `usage.print.allowed`, `usage.clipboard.allowed` and `usage.attachments.external_open` as booleans. **Fail closed:** a function whose setting the object does not hold, or holds in another type, is not allowed. Ignore a setting id or a word you do not know. The values hold until the database is opened again |
| `blobs` | object | What the server serves of a document's content: `max_size`, the largest size an upload may declare, in bytes; `push`, `true` where a push may name new content and the database takes changes now. Without `blobs` send no chunk request and push no reference to content; where `push` is `false` upload no chunk and push no reference to content |
| `audit` | object | The database's audit settings by setting id, as booleans: `audit.log_secret_access`, `true` where an administrator asks that each use of a password or another protected value in this database be recorded; `audit.reason.delete`, `true` where an administrator asks for a reason with each deletion of an entry. **Fail closed:** where the server cannot read a database's audit settings it answers `true` for both. For information: no request on this connection depends on them. Ignore a setting id you do not know |
| `release_secret` | null | Reserved; always `null` |

**Features added later** are announced by a member of this answer: where the member is absent or `null`, the app offers nothing of that feature and sends none of its requests. `recycle_bin` and `blobs` are such members. A member shapes what an app offers, never what the server allows: the server judges every request as ever.

### Close a Database

```json
{"end": true}
```

Without `field_key`. Closes the database in this REST session -- its field key wiped, its pull in progress and its editing hints ended -- and answers `200` with `{}`. Close a database when the app closes it. Opening it again is the only other way to replace its key; the REST session's end closes every database it opened.

### Errors

| Status | Word | When |
|--------|------|------|
| `400` | `malformed` | The body, the key, `field_key_epoch` or `writer` as above; `end` with a `field_key` |
| `404` | `not found` | The [database gate](#the-database-gate) |
| `409` | `writer of another principal` | The `writer` id was first used on this database by another user |
| `409` | `in use by an older client` | An older client that does not use the channel holds the database open; try again later |
| `409` | `too many sessions` | The REST session holds 64 open databases; close one first |
| `503` | `not served` | The database cannot be served at the moment |
| `503` | `busy` | The server does not take requests at the moment, or the request waited out its turn |

---

## Pull Changes

```
GET /v2.0/databases/{db}/sync?since=<cursor>&next=<part>
```

Answers the records the user may see and their changes since the cursor `since`. Without `since` it is a first pull: every record the user may see. `next` asks for the following part of a pull in progress.

### Query Parameters

| Parameter | Description |
|-----------|-------------|
| `since` | The cursor of the last completed pull or reconcile; absent for a first pull |
| `next` | The `next` of the previous part, to fetch the following part |

The server reads the query as it stands, without decoding it: a cursor and a `next` are base64url, which a URL holds as they are. A parameter given twice answers `400` with the word `malformed`; a parameter the route does not know is ignored.

### Response

`200 OK`, one part:

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 5120,
  "horizon": 0,
  "access_gen": 77,
  "complete": false,
  "next": "<part reference>",
  "records": [
    {
      "id": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02",
      "vv": {"a1b2c3d4e5f60718": 5368709121},
      "level": 1,
      "access": {"level": "read", "caps": ["create"], "own_permissions": false},
      "body": {"class": "entry", "...": "..."}
    }
  ],
  "withdrawn": ["0b9d7e44-1c2d-4e5f-8a6b-7c8d9e0f1a2b"]
}
```

The completing part has `"complete": true`, no `next`, and `cursor`, with `access_next` where it applies.

| Field | Type | Description |
|-------|------|-------------|
| `incarnation` | string | As in [Open a Database](#open-a-database) |
| `generation` | integer | The generation the pull runs to, fixed at its first part |
| `horizon` | integer | The lowest generation a cursor may name; a cursor below it is answered `reconcile` |
| `access_gen` | integer | A value per user and database that changes when the user's access may have changed. Compare it for equality only; on any difference, reconcile |
| `complete` | boolean | `true` in the completing part |
| `next` | string | Only where `complete` is `false`: send it as `next` for the following part. Good once, and only in this opening of the database until the pull completes, a new pull without `next` starts, or the database is closed or opened again |
| `cursor` | string | Only in the completing part: store it with the records of the pull, and send it as `since` next time |
| `access_next` | integer | Only in the completing part, where a permission of the user starts or ends ahead: that instant, in milliseconds since 1970-01-01 UTC. Pull again once it has passed |
| `records` | array | The records, each with `id`, `vv`, `level`, `access` and `body`. A record is never split across parts |
| `records[].access` | object | The user's access to the record: `level` -- `view`, `use`, `read` or `edit`; read a word you do not know as `view` --; `caps` -- the user's capabilities on the record, each word once, in this order: `create`, `delete`, `share` (give others permissions on it), `protect`, and on every record of a user who administers the database `manage` and `own`; ignore a word you do not know --; `own_permissions`, `true` where the record carries permissions of its own; `until`, where a permission that gives the access ends: that instant, in milliseconds since 1970-01-01 UTC. From that instant treat the record as inaccessible until you have pulled again |
| `withdrawn` | array of strings | In every part. In a pull since a cursor: ids of records that changed since and that the user may not see now, removed records included; drop them. It may name ids the app never held: ignore those. In a first pull it is empty |

**Parts.** An answer is at most 4 MiB, or one record. A part holds at least one record or withdrawn id, or the server has moved on through the database without finding anything to send in this part; an empty part with `next` is normal: store nothing and ask for the next part. One pull and one reconcile are in progress per open database at a time; a new one drops the earlier one's parts. A `next` the server does not know or no longer keeps answers `409` with the word `part expired`.

**Reconcile.** A cursor the server cannot continue from -- one it cannot read, one of another store of the database, a generation below `horizon` or beyond the database, a cursor of another `writer` id or another user -- is answered, instead of a part:

```json
{"reconcile": true, "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A", "generation": 5120}
```

`reconcile` is an answer, not an error: read the [manifest](#read-the-manifest). A pull in parts can end so as well, at a later part, where the user's access or the store changed since its first part; drop nothing you stored from the earlier parts. A cursor of another database answers `409` with the word `cursor of another database`: drop the cursor and reconcile.

### Errors

`400` `malformed`, `404` `not found`, `409` `no session`, `409` `part expired`, `409` `cursor of another database`, `503` `not served`, `503` `busy`; see [Words](#words).

---

## Read the Manifest

```
GET /v2.0/databases/{db}/manifest?next=<part>
```

A reconcile: every record the user may see, each with its version and the user's access, so that the app drops what it holds and the server no longer shows it, and fetches what it lacks. `next` asks for the following part, as in a pull.

The app reconciles when an answer is `reconcile`, when `incarnation` is new, when `access_gen` differs from its last answer's, and when its cursor lies below `horizon`.

### Response

`200 OK`, one part:

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 5120,
  "horizon": 0,
  "access_gen": 77,
  "complete": true,
  "cursor": "<cursor>",
  "manifest": [
    {
      "id": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02",
      "vv": {"a1b2c3d4e5f60718": 5368709121},
      "access": {"level": "use", "caps": [], "own_permissions": false}
    }
  ]
}
```

`incarnation`, `generation`, `horizon`, `access_gen`, `complete`, `next`, `cursor` and `access_next` as in a pull. Store `cursor` in the same step that stores the last record the manifest showed you to lack. A part may hold no row and not be complete; a later part can end with `reconcile`, as in a pull: start the reconcile again.

### Errors

`400` `malformed`, `404` `not found`, `409` `no session`, `409` `part expired`, `503` `not served`, `503` `busy`; see [Words](#words).

---

## Fetch Records

```
POST /v2.0/databases/{db}/sync/fetch
```

The records a manifest or a push answer showed the app to lack, by id.

### Request Body

```json
{"ids": ["6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02", "0d1e2f3a-4b5c-4d6e-8f70-8192a3b4c5d6"]}
```

`ids`: 1 to 1000 record ids. A body that is not a JSON object, and `ids` missing, given twice, empty, above 1000 or holding a value that is not a record id, answer `400` with the word `malformed`; another member is ignored.

### Response

`200 OK`:

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 5121,
  "access_gen": 77,
  "records": [],
  "missing": ["0d1e2f3a-4b5c-4d6e-8f70-8192a3b4c5d6"],
  "later": []
}
```

- `records`: as in a pull.
- `missing`: ids that do not exist, are of a class the channel does not deliver, or that the user may not see; drop them.
- `later`: ids the answer did not reach within its 4 MiB; ask for them again.
- An answer whose `incarnation` or `access_gen` differs from the manifest's means that the reconcile starts again.

### Errors

`400` `malformed`, `404` `not found`, `409` `no session`, `503` `not served`, `503` `busy`; see [Words](#words).

---

## Push Changes

```
POST /v2.0/databases/{db}/sync
```

Sends the app's pending changes as batches. Each batch is applied whole or not at all, in one change of the database.

### Request Body

```json
{
  "base": "<cursor>",
  "seen": 5122,
  "merge": "merge-1",
  "protocol": 2,
  "level": 1,
  "writer": "a1b2c3d4e5f60718",
  "floor": 36,
  "batches": [
    {
      "id": "b-7f3a",
      "units": [
        {"kind": "record", "sparse": true, "id": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02",
         "vv": {"a1b2c3d4e5f60718": 5368709121, "0f1e2d3c4b5a6978": 37}, "level": 1,
         "body": {"class": "entry", "groups": {"...": "..."}}, "token": "<record token>"}
      ],
      "tokens": []
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `base` | string | The stored cursor. A cursor the server cannot continue from answers `{"reconcile": true, "incarnation": ..., "generation": ...}` and applies nothing: reconcile, then push again |
| `seen` | integer | Optional: the highest generation the app has applied in full |
| `merge` | string | `merge-1` |
| `protocol` | integer | The protocol the sign-in declared; another number answers `400` with the word `protocol mismatch` |
| `level` | integer | The record-format level the app is built on: `1` |
| `writer` | string | The `writer` id the database was opened with; another one answers `409` with the word `writer not declared` |
| `floor` | integer | The counter just below the app's oldest pending change |
| `batches` | array | At most 64 batches. Each has an `id` of the app's choosing, unique in the push and echoed in the answer, its `units` and, where it moves a folder to the recycle bin or destroys one, the `tokens` of the records below it |

A unit's `kind` is `record` (a change of an existing record, with `sparse: true`), `create` or `purge` (a record destroyed from the recycle bin); its `id`, `vv`, `level`, `body` and `token` follow the record format. **A pushed group is the whole version:** what an app leaves out of it, it removes, so "ignore what you do not know" holds for the members of messages, not for a record's `body` -- an app keeps what it does not know inside a group it rewrites, or does not edit that record.

The whole push answers `400` with the word `malformed` only where a unit cannot be read at all (not a JSON object, no `kind`, no `id`, a member twice); every other fault rejects that unit's batch, and the other batches go on.

A change pushed over REST carries `rest/` and the version the sign-in declared as its client label (at most 64 characters), which the history shows as `client`.

### Response

`200 OK`:

```json
{
  "generation": 5123,
  "contiguous": true,
  "floor": 37,
  "batches": [
    {"id": "b-7f3a", "outcome": "merged",
     "records": [], "withdrawn": [], "later": [],
     "receipts": [{"counter": 37, "record": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02", "groups": ["credential"],
                   "outcome": "merged", "generation": 5122}],
     "history": [], "drop": [], "filed": [], "clock_anomaly": []},
    {"id": "b-7f3b", "outcome": "rejected",
     "units": [{"id": "0d1e2f3a-4b5c-4d6e-8f70-8192a3b4c5d6", "reason": "tree", "detail": "parent missing"}],
     "records": [], "withdrawn": [], "later": [], "drop": []},
    {"id": "b-7f3c", "outcome": "deferred", "reason": "read-only"}
  ]
}
```

| Field | Description |
|-------|-------------|
| `generation` | The database's generation after the push's last change; for a push that changed nothing, the generation at its start |
| `contiguous` | `true` where no other change lies between `max(base, seen)` and this push's changes |
| `floor` | The floor the server now holds for this `writer` id |
| `batches[].outcome` | `accepted` or `merged`: applied. `rejected`: refused, nothing of the batch applied; `units` and `reason` say why. `deferred`: nothing decided; the batch stays pending and goes again later. Read an `outcome` you do not know as `merged` |
| `records`, `withdrawn`, `later` | The records the batch touched as they stand after the whole push, each with `id`, `generation`, `vv`, `level`, `access`, `body` and `token`, its record token; the ids of those the user may not see after the push (drop them); the ids the answer did not reach within its 4 MiB (fetch them) |
| `receipts` | Per change: `counter`, `record`, `groups`, `outcome`, `generation` |
| `history`, `drop`, `filed`, `clock_anomaly` | `history` is always empty; `drop` names local history items the app drops; `filed`, conflict items the batch filed; `clock_anomaly`, records whose change took the server's clock |
| `units` | A rejected batch: `{id, reason, detail}` for every unit of the batch |
| `reason` | A rejected batch's reason where one applies to the batch: `writer level`, `duplicated writer identity`, `too large`. A deferred batch's reason: `read-only` (the database takes no changes now), `busy` (a heavy task holds the database, or a write failed; that batch and every later one), `receipts` (the server's record of the app's changes is full; that batch and every later one), `blob incomplete` (the content the batch names is not uploaded whole) |

A unit's `reason` is one of `deleted on the server`, `changed on the server` (a purge of a record that changed since the app last received it: once the app holds the newer version, the user may purge again), `stale`, `duplicated writer identity`, `principal` (a change whose stamp names another user than the signed-in one), `protected`, `compartment entry read-only`, `not in this version`, `not authorised`, `incomplete`, `invalid`, `too large`, `tree`, `batch` (a unit refused because another unit of its batch was), with a `detail` where one applies (for `tree`: `loop`, `parent missing`, `parent trashed`, `changed below`, and `not in bin` for a purge of a record that is not in the recycle bin). An unknown reason of a rejected batch is a refusal; an unknown reason of a deferred batch is a wait.

Push a deferred batch again at the [backoff](#words). A push with more than 64 batches answers `413` with the word `too large` and applies nothing, and a push above 16 MiB is refused `413` before its body is read, without `word`: several batches go as several pushes; a batch is never split. A batch of more than 1 048 575 changes is rejected `too large`.

### Errors

`400` `malformed`, `400` `protocol mismatch`, `404` `not found`, `409` `no session`, `409` `writer not declared`, `409` `writer of another principal`, `409` `cursor of another database`, `413` `too large`, `500` `failed`, `503` `not served`, `503` `busy`.

---

## Editing Hint

```
POST /v2.0/databases/{db}/entries/{id}/editing
```

Tells the other users of the database that the user is editing the entry `{id}`: the server passes the hint on to their connected Windows clients. A hint is advisory: it locks nothing. It needs the [database gate](#the-database-gate), not an opened database.

### Request Body

```json
{"on": true}
```

`on`: `true` sets the hint or renews it, `false` ends it. The body may name the entry as `entry` as well; another id there answers `400` with the word `malformed`.

- Renew the hint every 60 seconds while the user edits the entry. A hint lapses 180 seconds after its last renewal, and ends at `on: false` and with the REST session.
- A hint belongs to this REST session alone; another session's hint on the same entry, of the same user or another, is its own.
- The start of a hint is audited as the Windows client's lock of the entry is; a renewal writes nothing.
- An app receives no hints of other users over REST.

### Response

`200 OK` with `{}`.

### Errors

`400` `malformed`, `404` `not found` (the gate), `404` `not visible` (an entry the user may not see, one that does not exist and a folder alike), `429` `rate limited` (more than 20 editing hints in 10 seconds in the REST session; `Retry-After` and `error.retry_after`), `503` `not served`, `503` `busy`.

---

## History

```
GET  /v2.0/databases/{db}/entries/{id}/history?from=<item>
GET  /v2.0/databases/{db}/entries/{id}/history/{item}
POST /v2.0/databases/{db}/entries/{id}/history
```

The same routes exist under `folders`: `entries` and `folders` are two words for one route, and the record's class is not judged by them. A record's history is answered where the user has read access to the record now, an entry or a folder; every other id -- one that does not exist, one the user sees below `read`, a record that is neither an entry nor a folder -- is answered exactly as one that does not exist. History is never part of a pull.

### History List

`GET .../history` lists the record's history items, newest first, metadata only: no value travels.

| Parameter | Description |
|-----------|-------------|
| `from` | Optional: the `next` of the previous answer, to list the rest |

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 5121,
  "access_gen": 77,
  "record": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02",
  "items": [
    {"id": "1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b", "origin": "1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
     "cause": "edit", "change": [1761830400000, 0, "8f1e2d3c4b5a6978", 5368709121, "u:3D52A0C4-1B6E-4F7A-9C2D-5E8F10B2A7C1"],
     "by": "Alice Example", "client": "windows/20.0.0", "groups": ["name"], "level": 1}
  ],
  "complete": true
}
```

| Item field | Description |
|------------|-------------|
| `id` | The item's id, which [History Items](#history-items) names |
| `origin` | The change the item stands for; equal to `id` unless a later copy of the item is the kept one |
| `cause` | Why the item was written: `create`, `edit`, `move`, `trash`, `restore`, `restore-version`, `merge`, `conflict`, `ack`, `import`, `api`, `addon`, `convert`, `reseal`, `legacy-original`, `retire`, `recovered` or `legacy-import`; show a word you do not know as text |
| `change` | Who made the change, when and through which app, in the record format's stamp form |
| `by` | The display name of the user who made the change, as the server knows the user now; absent where the change is no user's |
| `client` | The app that made the change, `<platform>/<version>` |
| `note` | The reason text, where the database asked for one |
| `author`, `at`, `at.legacy_local` | A converted item's original author and time |
| `groups` | The groups the change replaced |
| `conflict` | On an item of the cause `conflict`: `filed` or `acknowledged` |
| `level` | The item's record-format level |

An answer is at most 4 MiB. Where items remain, it ends `"complete": false` and `next`, the id of the first item it did not hold: send it as `from`. A `from` the record's list does not hold answers `409` with the word `part expired`: list again without `from`. Where a later part's `incarnation`, `generation` or `access_gen` differs from the first part's, list again from the start.

For a record whose history the user may not read:

```json
{"incarnation": "q0uL0n3fZ8kq3m7c1yVb2A", "generation": 5121, "access_gen": 77,
 "missing": ["6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02"]}
```

Drop the history items you hold of that record, and show none; its visibility stays the pull's.

### History Items

`GET .../history/{item}` answers one item; `POST .../history` with `{"items": ["<item id>", ...]}` -- 1 to 1000 ids, each at most once -- several. The answer is the same:

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 5121,
  "access_gen": 77,
  "record": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02",
  "items": [{"id": "1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b", "level": 1, "body": {"class": "hist", "...": "..."}}],
  "missing": [],
  "later": []
}
```

- `items[].body`: the old version, its values sealed under the field key as a pull delivers a record at `read`. A value the user could not read in the record's current version, and a folder the user cannot see, are left out and named in the body's `redacted`.
- `missing`: an item the record's list does not hold, or whose values cannot be delivered. `later`: the ids the answer did not reach within its 4 MiB.
- For a record whose history the user may not read, the `missing` form of the list above, whatever items the request names.
- A request that delivers at least one item is recorded in the audit trail, naming the record and the number of items -- never a value.

### Errors

`400` `malformed` (a `record` in the body that names another record, a `from` or an item id that is not an id, `items` empty, above 1000 or with an id twice), `404` `not found` (the gate), `409` `no session`, `409` `part expired`, `429` `rate limited` (more than 20 history requests in 10 seconds in the REST session; `Retry-After` and `error.retry_after`), `503` `not served` (also where the record's history cannot be read), `503` `busy`.

---

## Document Chunks

A document's content, a certificate entry's files and an attachment travel apart from the record, as chunks of their stored, encrypted form; the record holds the reference. The server never opens a chunk: it checks a chunk's form and stores or returns its bytes. An app uploads the chunks first and then pushes the record that names them. Both routes need an opened database and count together against 64 requests a second in the REST session (`429` `rate limited` beyond it, with `Retry-After` and `error.retry_after`).

### Upload a Chunk

```
PUT /v2.0/databases/{db}/blobs/{blob}?chunk=<n>&chunks=<n>&chunk_size=<n>&size=<n>
```

The request body is exactly one chunk frame, as octets (`Content-Type: application/octet-stream`): 52 to 1 048 628 bytes, as the app sealed it. `{blob}` is the content's id, 8-4-4-4-12 hexadecimal digits in either letter case.

| Parameter | Description |
|-----------|-------------|
| `chunk` | The index of the chunk this frame carries, below `chunks` |
| `chunks` | The number of chunks: `max(1, ceil(size / chunk_size))` |
| `chunk_size` | The chunk size, from 65536 to 1048576 bytes |
| `size` | The size of the whole content before encryption, at most `blobs.max_size` (64 MiB) |

Every parameter is required, once, as digits only. The first chunk of an upload fixes `chunks`, `chunk_size` and `size`; a later chunk that declares otherwise answers `400` with the word `malformed`, as does a frame that does not fit its declaration.

```json
{"held": [[0, 1]], "complete": false}
```

`held` lists the chunks the upload holds after this request, as ascending ranges `[first, last]`; `complete` is `true` once it holds every chunk. A chunk sent again with the same bytes is answered as stored, and with other bytes `400` `malformed`. Every chunk `held` names is on the server's disk. An upload belongs to the user and the database alone, lives 24 hours after its last chunk and at most 72 hours after its first, and is removed once a push names it. Push the record that names the content after `complete`.

| Status | Word | When |
|--------|------|------|
| `400` | `malformed` | The frame or the query, as above |
| `403` | `not authorised` | The user may change nothing in the database |
| `413` | `too large` | `size` above `blobs.max_size`, or a new upload whose `size` would take the database past 4 GiB, its documents included |
| `429` | `quota` | A new upload that would take the user past 128 MiB or 256 uploads on the database, or past 256 MiB on the server; the server first ends the user's own uploads there that took no chunk for 15 minutes. `error.retry_after`: at least the seconds until one of the uploads that count ends its life. Push the records whose content is complete first |
| `503` | `not served` | The server's disk for uploads is nearly full |

And, as on every route of the channel: `404` `not found` (the gate), `409` `no session`, `429` `rate limited`, `500` `failed` (the server could not store the chunk), `503` `busy`.

### Download Chunks

```
GET /v2.0/databases/{db}/blobs/{blob}?record=<id>&chunk=<n>&count=<n>
```

The stored chunks of the content `{blob}`, by the entry `record` that names it. `chunk` is the first chunk wanted, from `0`; `count` is a hint, at least `1`. Every parameter is required.

```json
{
  "incarnation": "q0uL0n3fZ8kq3m7c1yVb2A",
  "generation": 5121,
  "access_gen": 77,
  "record": "6f1c3a2e-0d4b-4c7a-9e21-3b5f7a1c9d02",
  "blob": "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
  "chunks": 3,
  "frames": [262196, 262196],
  "data": "<the frames, concatenated, in base64url>"
}
```

- `frames` lists the length of each frame in `data`'s order; `chunks` is the content's number of chunks. An answer holds at most `count` frames within 1 MiB, and at least one where `chunk` is below `chunks`; a `chunk` at or past `chunks` answers `"frames": []` and no `data`.
- `data`: the frames, each exactly as the server stores it, concatenated, in base64url without padding. Check each frame and the whole set as the record format says, with the key the reference gives you.
- Where the user may not read the entry, the entry does not name the content, or the server does not hold it whole, the answer is `{"incarnation": ..., "generation": ..., "access_gen": ..., "missing": ["<record id>"]}`: drop what you fetched, pull, and start again from the record.
- Download only for a read the user asks for -- open, view, save, print -- and keep the frames in memory until the read is done.
- The first download of a content in an opening of the database is recorded in the audit trail.

Errors: `400` `malformed` (a parameter missing, twice or not of its form), `404` `not found` (the gate), `409` `no session`, `429` `rate limited`, `500` `failed`, `503` `not served`, `503` `busy`.

---

## Errors

### The Error Object

A refused channel request answers the published [error object](overview.md#error-format) with the member `word`:

```json
{
  "error": {
    "code": 409,
    "message": "Please open the database for synchronisation first.",
    "word": "no session"
  }
}
```

- The HTTP status is authoritative; `error.code` is the status, or `4039` for `protocol required`.
- `error.word` is stable English and never localized: match it, never `message`, which is a text for people.
- `error.retry_after`, where present, is the number of seconds to wait; the response then also carries `Retry-After`.
- Ignore members of `error` you do not know.
- A pull's `reconcile`, a fetch's `missing` and `later` and a batch's outcome are answers, not errors: they come with `200`.

### Words

| Word | Status | Meaning | What the app does |
|------|:------:|---------|-------------------|
| `malformed` | `400` | The request, a parameter or a member is not of its form | Nothing: a defect of the app |
| `protocol mismatch` | `400` | A push's `protocol` is not the sign-in's | Nothing: a defect of the app |
| `not signed in` | `401` | The account is no longer signed in, or it is disabled | Sign in again; where the new session is answered so too, stop sending channel requests and show the server's text |
| `not permitted` | `403` | A session of the `admin` scope | Sign in with the client scope |
| `protocol required` | `403` / `4039` | A client-scope session that declared no protocol | Sign in with `client.protocol` |
| `not authorised` | `403` | An upload of a user who may change nothing in the database | Nothing |
| `not found` | `404` | The [database gate](#the-database-gate) | Open the database again at the backoff; see Access lost |
| `not visible` | `404` | An editing hint for an entry the user may not see | Nothing |
| `no session` | `409` | The database is not opened in this REST session | Open it, then send the request again |
| `writer not declared` | `409` | A push's `writer` is not the one the database was opened with | Open the database with that `writer` id, then push again |
| `writer of another principal` | `409` | The `writer` id was first used on this database by another user | Draw a new `writer` id and open the database again |
| `in use by an older client` | `409` | An older client holds the database open | Backoff |
| `too many sessions` | `409` | 64 databases are opened in this REST session | Close one first |
| `cursor of another database` | `409` | The cursor belongs to another database | Drop the cursor; reconcile |
| `part expired` | `409` | A `next` or a history `from` the server does not hold | Pull again since the stored cursor, reconcile from the start, or list the history again without `from` |
| `too large` | `413` | A push or an upload above its bound | Nothing for that request: several batches go as several pushes |
| `quota` | `429` | An upload past the user's quota | Push complete content first; then after `retry_after` |
| `rate limited` | `429` | A rate bound, or too many requests of the REST session waiting | After `retry_after` |
| `failed` | `500` | A failure on the server | Backoff |
| `not in this version` | `501` | A request this server does not serve | Hide the feature (below) |
| `not served` | `503` | The database or its history cannot be served at the moment, or the server's disk for uploads is nearly full | Backoff |
| `busy` | `503` | The server does not take requests at the moment, a heavy task holds the database, or the request waited out its turn | Backoff |

**Backoff:** 1 second, doubling to 60 seconds, `Retry-After` honoured. **An unknown word is a wait:** a `word` you do not know, under any status, reads as a wait at the backoff; the pending changes stay as they are.

### A Status with No Word

Not every answer comes from the channel. The checks before it, the HTTP layer and a proxy on the way answer by their status alone, and a proxy's body may be no JSON. Read an answer without `word`, or one that is no JSON, by its status, never as an unknown word:

| Status | What stands behind it | What the app does |
|--------|-----------------------|-------------------|
| `400` | A request the checks before the channel refuse | Nothing: a defect of the app |
| `401` | The token refused: expired, ended or invalid, or its account disabled or deleted | Sign in again, then open the databases again; the pending changes stay |
| `403` | A `POST` or `PUT` on a [mirror server](overview.md#http-status-codes), which accepts only `GET` with a token; the platform and minimum-version policies (`error.code` `4036`, `4037`) | Stop sending, show the server's text, keep the pending changes |
| `404` | A route this server does not know | Hide the feature. Only the word `not found` starts the check of Access lost |
| `405` | A method the route does not take; `Allow` names the methods it takes | Nothing: a defect of the app |
| `413` | A body above its bound, refused before it is read | As `too large` |
| `429` | An address locked out after failed sign-ins | Backoff |
| `500`, `502`, `503`, `504` | The server, or a proxy before it | Backoff |

### Features Not Served

On a channel request the app knows, `501` with the word `not in this version` means that this server does not serve it. The app hides the feature and sends that request no more to this server, until the answer of [Open a Database](#open-a-database) announces it; nothing else changes: the database stays open and the pending changes stay as they are. A channel route reserved for a later feature answers so, before its body is read and before the database is looked up.

---

## Bounds

| Bound | Value |
|-------|-------|
| An answer of a pull part, a manifest part, a fetch, a push, a history list or history items | At most 4 MiB, or one record. A later server may send more: do not size a buffer by it |
| A push | At most 16 MiB of body and 64 batches; a batch at most 1 048 575 changes |
| A fetch, history items | At most 1000 ids |
| Open databases | At most 64 per REST session |
| REST sessions | At most 32 per account (see [Sessions](authentication.md#sessions)) |
| A request body | A push at most 16 MiB, an uploaded chunk at most 1 048 628 bytes, every other channel route at most 1 MB -- above it `413` before the body is read, without `word`; the body of [Open a Database](#open-a-database) at most 4096 bytes (`400` `malformed`) |
| Waiting for the turn | At most 10 seconds (`503` `busy`); at most 4 requests waiting (`429` `rate limited`, `retry_after` `1`) |
| Editing hints | 20 per 10 seconds per REST session; renewed every 60 seconds, lapsing after 180 seconds |
| History | 20 list and item requests together per 10 seconds per REST session |
| Chunks | 64 uploads and downloads together per second per REST session; a frame 52 to 1 048 628 bytes; a chunk size 64 KiB to 1 MiB; a content at most 64 MiB; at most 1 MiB of frames per download |
| Uploads | Per user, 128 MiB in at most 256 uploads on a database and 256 MiB on the server, each counted at its declared size and at least one chunk; an upload lives 24 hours after its last chunk and at most 72 hours after its first |
| A database's size | At most 4 GiB, its documents included |
| Client label | `rest/<version>`, at most 64 characters |
