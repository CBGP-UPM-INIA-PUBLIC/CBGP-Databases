# Configuration

Once the two GraphDB repositories exist (see [Installation](installation.md)),
the application needs a `.env` file telling it how to reach them and a few
other things. Copy the template and fill it in:

```bash
cp .env.example .env
```

`.env` is deliberately excluded from version control (it holds real
passwords) — `.env.example` is the checked-in template with safe
placeholder values, always kept up to date with whatever the application
actually reads. If a setting described below doesn't appear in
`.env.example`, that's worth flagging — it means this page or the template
has drifted out of sync with the code.

The application refuses to start at all if a handful of these are missing
— that's deliberate, so a misconfigured instance fails immediately and
loudly on startup rather than serving a broken login page.

## Login accounts

```
CBGP_USERS={"someadmin":{"password":"change-me","role":"admin"},"someuser":{"password":"change-me","role":"user"}}
```

Every login this instance accepts, as a single-line JSON object. Each
entry's key is the username; `password` is checked as plain text against
whatever's typed into the login form (there's no separate user-management
screen — accounts are managed by editing this value and restarting);
`role` is either `"admin"` (full read/write access to every form) or
`"user"` (the public-facing, submission-only forms described in the
[User Guide](user_guide.md)). Add as many accounts as needed, one entry per
person.

```
CBGP_SECRET=change-me-to-a-long-random-string
```

A long, random, secret string used to cryptographically sign session
cookies — anyone who knows this value could forge a logged-in session, so
treat it the same as a password. Generate one with, e.g.:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

There's no way to "rotate" this without invalidating every currently
logged-in session (which is harmless — people just have to log in again),
so changing it is safe to do at any time.

## Ontology

```
CBGP_KB=https://w3id.org/CBGP-App
```

Where the application reads its ontology from — this is what makes the
whole system work the way described in [Philosophy & Design](philosophy.md):
every field, form, and label comes from here, read fresh over the network
each time the application needs it (or when an administrator triggers a
manual refresh). The public default shown above is correct for this
institute's normal deployment; there's no reason to change it unless
running a separate, private fork of the ontology for testing.

## GraphDB connection

```
GRAPHDB_HOST=localhost:7200
GRAPHDB_USER=change-me
GRAPHDB_PASS=change-me
GRAPHDB_DBNAME=kbdatabase2
GRAPHDB_HISTORY=kbhistory
```

`GRAPHDB_HOST` is where GraphDB itself listens — `localhost:7200` is
correct when running the application directly on the same machine as
GraphDB; running via `docker compose` overrides this automatically to
reach the `graphdb` container by its service name instead, so it's safe to
leave this at the default even in a Docker deployment (see
[Installation](installation.md)'s note about this).

`GRAPHDB_USER`/`GRAPHDB_PASS` are the credentials GraphDB itself was
configured with (set up separately, in GraphDB's own security settings, if
GraphDB security is enabled — this isn't something `.env` controls).

`GRAPHDB_DBNAME` and `GRAPHDB_HISTORY` must exactly match the two
repository IDs created during [Installation](installation.md) — one
mismatched character here is the most common reason a freshly-installed
instance shows no data or won't start. Two optional variables,
`HISTORY_USER`/`HISTORY_PASS`, exist only for the unusual case where the
history repository needs *different* credentials than the current-state
one — leave them unset (the normal case) and they quietly reuse
`GRAPHDB_USER`/`GRAPHDB_PASS`.

## Admin email notifications

```
NOTIFY_TO=admin@example.org
NOTIFY_FROM=cbgp-databases@example.org
NOTIFY_UN=change-me
NOTIFY_PW=change-me
NOTIFY_SMTP_ADDRESS=smtp.example.org
NOTIFY_SMTP_PORT=587
NOTIFY_SMTP_STARTTLS=true
NOTIFY_SMTP_AUTH=login
```

Whenever someone submits a form through the public-facing User side of the
application (see [User Guide](user_guide.md)), an email goes out to
`NOTIFY_TO` so an administrator knows there's something new to review.
`NOTIFY_TO` accepts either a single address or a comma-separated list, for
notifying more than one person. The remaining `NOTIFY_SMTP_*`/`NOTIFY_UN`/
`NOTIFY_PW` values are ordinary outgoing-mail-server settings — whatever an
institute's own mail server (or mail-sending service) requires; ask
whoever manages that system for the right values, the same as configuring
any other application to send mail through it.

## A note on security

Every password and secret on this page — login passwords inside
`CBGP_USERS`, `GRAPHDB_PASS`, `NOTIFY_PW`, `CBGP_SECRET` — lives *only* as
an environment variable the application reads once at startup. There is no
user/password database inside the application itself: no table of
accounts, no password hashes, nothing stored in GraphDB or anywhere else
the application controls. There's nothing there for someone to break into
and steal, because none of it is stored there in the first place.

`.env` is the *convenient* way to supply these values — a plain file that
gets read once at startup — not the *only* way, and not a requirement.
Nothing about the application needs these values to ever touch disk at
all: any mechanism that can set real process environment variables works
exactly as well — a hosting platform's own secrets manager, `docker run -e
VAR=value`, a CI/CD pipeline's secret injection, or systemd's
`Environment=`/`EnvironmentFile=`. If a deployment's security policy
prefers secrets are never written to a file, skip `.env` entirely and
inject the same variables through whatever mechanism that platform
normally uses for secrets — the application has no idea, and doesn't
care, which mechanism supplied them.

## After changing `.env`

The application only reads `.env` once, at startup — editing it while the
application is already running has no effect until it's restarted:

- Running natively: stop and re-run `ruby run.rb`.
- Running via `docker compose`: `docker compose up -d` again picks up a
  changed `.env` automatically (Docker Compose re-creates a container
  whose configuration changed).

Note that this is different from *ontology* changes, which the running
application picks up on the next `/cbgp/refresh` without needing a
restart at all — see [Philosophy & Design](philosophy.md).
