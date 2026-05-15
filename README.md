# TesseraBX

A multi-tenant help-desk and customer support platform. A ColdBox 8 application running on the BoxLang runtime, deployed as a Docker stack, with optional AI integration through the `bx-ai` BoxLang server module.

The durable specification lives in [CLAUDE.md](CLAUDE.md). The phased build order lives in [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md). Read those two files before changing anything substantive.

## What this is

One help-desk provider runs TesseraBX and uses it to serve multiple client companies (each modeled as an `Organization`). Client users submit and track support requests through a self-service portal (`/`), an embeddable widget (`/widget`), or email. The provider's agents and technicians work tickets through a separate dashboard (`/agent`), with the administration surface nested inside it at `/agent/admin`. A versioned REST API serves `/api`.

A single application composed of sixteen independently testable ColdBox modules:

```
core  contacts  audit  tickets  agent (admin)  portal  widget
knowledgebase  channels  automation  sla  ai  notifications  reporting  api
```

The `admin` module is a child module physically nested inside `agent` and resolves to `/agent/admin`.

## Running the dev stack

The development stack is self-contained: no reverse proxy, no external Docker network, no TLS, the application's HTTP port published directly to the host. It adds Mailpit (SMTP trap) and Adminer (database inspector) on top of the base stack.

```
cp .env.example .env
docker compose -f compose.yaml -f compose.dev.yaml up --build
```

Once everything is healthy:

| Surface       | URL                              |
|---------------|----------------------------------|
| Client portal | http://localhost:8080/           |
| Agent surface | http://localhost:8080/agent      |
| Admin surface | http://localhost:8080/agent/admin|
| REST API      | http://localhost:8080/api/v1     |
| Widget        | http://localhost:8080/widget     |
| Health check  | http://localhost:8080/health     |
| Mailpit UI    | http://localhost:8025/           |
| Adminer       | http://localhost:8081/           |

Database migrations run automatically when the `app` container starts (via `docker/app-entrypoint.sh`). Seed the two test accounts:

```
docker compose exec app box migrate seed run
```

After seeding:

- Client: `client@example.com` / `password` (Organization Admin of "Acme Corp")
- Agent:  `agent@example.com`  / `password` (admin-flagged agent, can reach `/agent/admin`)

## Running the production stack

TesseraBX deploys by building the image from the working tree on the deploy host. There is no container registry. Each environment pulls the repo and runs `docker compose up --build`, so the host always serves the code on its current branch.

### Prerequisites on the deploy host

- Docker Engine and the `docker compose` CLI plugin.
- An external Docker network already created and owned by the reverse proxy. Its name goes in `.env` under `PROXY_NETWORK`.
- A reverse proxy (Nginx, Traefik, Caddy, whatever you run) attached to that network, owning TLS / HTTPS / certificates. The compose stack itself speaks plain HTTP; the proxy terminates TLS.
- A populated `.env` file in the project root (never committed). See `.env.example` for every variable.

### First-time deploy

```
git clone https://github.com/oistechnologies/tesserabx.git /opt/tesserabx
cd /opt/tesserabx
cp .env.example .env
# edit .env with real credentials, PROXY_NETWORK, CBFS_S3_* for production, etc.
docker compose up -d --build
```

Migrations run automatically as the `app` container starts. The seeder is **dev-only** and should not be run in production.

### Updating an existing deploy

```
cd /opt/tesserabx
git pull
docker compose up -d --build
```

`docker compose up --build` re-runs the Dockerfile from the new working tree. Containers are rebuilt and recreated; the named volumes (`db_data`, `redis_data`) and the anonymous volume holding the BoxLang server home persist across this. Migrations run automatically on the new `app` container at start. `depends_on: condition: service_healthy` makes the worker and scheduler wait for the new app to be healthy before they swap in.

### What the proxy must route to `app:8080`

The four path groups are served by the same `app` container; route everything that starts with these to it:

- `/` — the client portal surface
- `/agent` — the technician dashboard, with `/agent/admin` nested inside
- `/api` — the versioned REST API
- `/widget` — the embeddable widget intake

The proxy is also responsible for forwarding the usual headers (`X-Forwarded-For`, `X-Forwarded-Proto`, `Host`) so the application sees the correct client address and original protocol.

### Things that are NOT in scope for this manual flow

These are tracked as Phase 6 hardening; the manual recipe above is what we ship until then.

- Automated CD (no git-push triggered deploys; no GitHub Actions deploy job).
- Image registry. There is no `docker push` step. Image stays local to each deploy host.
- Rollback automation. Roll back by `git checkout <previous-sha> && docker compose up -d --build`.
- Pre-deploy database backups. Run `pg_dump` manually before a risky migration until the nightly backup task in Phase 3 lands.
- Zero-downtime restarts and blue/green. Compose stops the old container before starting the new one; expect a short cutover window.
- Secrets management beyond `.env`. The `.env` file on the host is the single source.

## Database backups

A nightly database backup task (built in Phase 3) runs `pg_dump`, compresses the dump, and writes it to the configured CBFS provider under a dated path. It prunes dumps older than `BACKUP_RETENTION_DAYS`.

> **Warning.** When `CBFS_DEFAULT_PROVIDER=local` in production, the backup file lands on the same host as the database. That is only partial protection; if the host fails, both the database and its backups are lost together. Setting `CBFS_DEFAULT_PROVIDER=s3` (with the Backblaze B2 credentials populated) places backups offsite and negates that concern. Disaster recovery beyond nightly backups (point-in-time recovery, tested restores, replication) is the operator's responsibility.

## AI is optional

TesseraBX is fully functional with no AI configuration provided. When `AI_ENABLED=false` (the default in `.env.example`), the entire AI layer is inert: no AI UI elements render anywhere, no AI cbq jobs are enqueued, and feature modules take the non-AI code path. The `ai` module is the only code in the entire repository that imports `bx-ai`; every other module reaches AI through the `ai` middleware facade.

## Repository layout

```
Application.cfc              ColdBox bootstrap
index.cfm                    front-controller placeholder (ColdBox 8 convention)
box.json                     CommandBox + dependency manifest
server.json                  CommandBox server config; declares BoxLang modules
config/                      ColdBox / CacheBox / WireBox / Router / Scheduler
config/boxlang.json          BoxLang runtime config and datasource definition
handlers/                    root-level handlers (Main)
includes/helpers/            ApplicationHelper.cfm and friends
layouts/                     reserved for root-level layouts (rare)
modules_app/                 the sixteen app-owned modules live here
modules/                     CommandBox-installed third-party modules (gitignored)
resources/database/migrations  cfmigrations migration files
resources/database/seeds       development seeders
resources/tasks/             worker and scheduler entrypoint tasks
docker/                      worker and scheduler entrypoint shell scripts
docs/                        durable specs (BUILD-PLAN.md and per-module specs)
tests/                       TestBox runner and top-level specs
```

## Running tests

```
docker compose exec app box migrate up
docker compose exec app box testbox run
```

CI runs the same TestBox specs on a disposable PostgreSQL container (with `pgvector`) and Redis on every push to `main` and every pull request.

## Phase 0 status

Phase 0 is complete when:

- The dev stack starts cleanly with `docker compose -f compose.yaml -f compose.dev.yaml up`.
- Both surface layouts render at `/` and `/agent`.
- A test client user and a test agent user can each log in and reach their respective surface.
- `/agent/admin` returns HTTP 403 for a non-admin agent.
- CI is green.

See [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md#phase-0--scaffolding) for the full Phase 0 exit condition.
