# Security Policy

This repository holds the **documentation, OpenAPI specifications, and example
scripts** for the Password Depot Enterprise Server REST API. Password Depot is a
password manager, so we take security very seriously and appreciate responsible
disclosure.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report privately through one of these channels:

1. **GitHub private vulnerability reporting** (preferred) — on this repository,
   go to the **Security** tab → **Report a vulnerability**. This opens a private
   advisory visible only to you and the maintainers.
   <!-- Maintainers: enable this under Settings → Code security and analysis →
        "Private vulnerability reporting" before publishing the repo. -->
2. **Email** — `info@password-depot.de`.

Please include:

- A description of the issue and its potential impact.
- Steps to reproduce (proof-of-concept, affected endpoint, request/response if
  relevant).
- The PD Server version and the REST API version involved (v1.0 or v2.0).
- Any suggested remediation, if you have one.

We aim to acknowledge reports within **5 business days** and to keep you updated
as we investigate. Please give us a reasonable window to release a fix before any
public disclosure.

## Scope

**This repository** — report problems in the material published here: insecure
patterns in the example scripts (`examples/`), misleading or incorrect security
guidance in the docs (`docs/`), or errors in the OpenAPI specs (`openapi/`) that
could lead integrators to build something unsafe.

**The Password Depot Server and the REST API implementation** are a separate,
proprietary product and are **not** in this repository. Vulnerabilities in the
server or the live API (authentication, authorization, cryptography, data
handling, etc.) are still very welcome — report them to the same contact above and
note that they concern the **server / API implementation**, not these docs.

> The example scripts intentionally relax TLS certificate validation in places
> (e.g. `curl -k`, `-SkipCertificateCheck`) so they can run against a server's
> self-signed certificate during evaluation. Do **not** carry that over to
> production — always validate against a properly issued certificate.

## Supported versions

The documentation tracks two API versions: **v1.0** (stable) and **v2.0**.
Fixes to the docs, specs, and examples are applied to the current state of this
repository.
