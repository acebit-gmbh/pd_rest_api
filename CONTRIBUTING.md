# Contributing to the Password Depot REST API documentation

Thanks for your interest in improving the docs! This repository contains the
**reference documentation, OpenAPI specifications, and runnable examples** for the
Password Depot Enterprise Server REST API. (The server itself is a separate,
proprietary product and is not part of this repo.)

For security issues, **do not** open a public issue — follow the
[Security Policy](SECURITY.md) instead.

## What lives here

```
docs/      Markdown reference, split into v1.0/ and v2.0/
examples/  Runnable client examples (PowerShell, curl, Python) per version
openapi/   OpenAPI 3.0 specifications per version
overrides/ MkDocs Material theme overrides (header, logo)
```

## Building the docs locally

The docs are built with [MkDocs](https://www.mkdocs.org/) and the
[Material theme](https://squidfunk.github.io/mkdocs-material/).

```bash
# MkDocs 2.0 is currently incompatible with the Material theme — pin to 1.x.
pip install "mkdocs>=1.6,<2.0" mkdocs-material

# Live preview (pick a version):
mkdocs serve -f mkdocs.v1.yml
mkdocs serve -f mkdocs.v2.yml
```

`build_site.bat` builds both versions into `site/` for deployment.

## Conventions

- **Keep `openapi/` and `docs/` in sync.** When you change an endpoint's request
  or response, update both the Markdown reference under `docs/<version>/` and the
  matching `openapi/<version>/openapi.yaml`. The OpenAPI spec is consumed by
  tooling (including the Server Manager), so drift between them is a bug.
- **Use neutral placeholders — never real data.** Hosts must be `your-server` or a
  `*.example.com` name; emails and domains use `example.com`; sample IP addresses
  use the RFC 5737 ranges (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`).
  Do **not** commit real hostnames (internal or customer), real email addresses,
  real customer data, or working credentials.
- **Keep examples parameterized and runnable.** Scripts should take the server,
  username, and password as parameters — don't hard-code a server name or a
  password into a script.
- **Keep v1.0 and v2.0 parallel** in structure where features overlap, and record
  version-specific changes in the matching `changelog.md`.

## Submitting changes

- Branch from `master` and keep pull requests focused on a single change.
- Describe **what** changed and **why**; link any related issue.
- If you changed an endpoint, confirm the docs and the OpenAPI spec agree.
- Build the affected docs locally (`mkdocs serve -f mkdocs.v<n>.yml`) and check
  that your pages render and links resolve.

## Reporting issues

Open a GitHub issue for documentation errors, unclear guidance, or spec/doc
mismatches — include the version (v1.0 / v2.0) and a link to the affected page.
For security vulnerabilities, see [SECURITY.md](SECURITY.md).
