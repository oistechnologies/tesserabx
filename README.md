# TesseraBX

A multi-tenant help-desk and customer support platform. A ColdBox 8 application running on the BoxLang runtime, deployed as a Docker stack, with optional AI integration through the `bx-ai` BoxLang server module.

The durable specification lives in [CLAUDE.md](CLAUDE.md). The phased build order is in [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md), and the parallel extensibility track is in [docs/EXTENSIBILITY-PLAN.md](docs/EXTENSIBILITY-PLAN.md). Read those before changing anything substantive.

## What it is

One help-desk provider runs TesseraBX and uses it to serve multiple client companies, each modeled as an `Organization`. Client users submit and track support requests through a self-service portal at `/`, an embeddable widget at `/widget`, or email. The provider's agents work tickets through a separate dashboard at `/agent`, with the administration surface nested inside it at `/agent/admin`. A versioned REST API serves `/api`.

A single application composed of seventeen independently testable ColdBox modules:

```text
core  contacts  audit  tickets  agent (admin)  portal  widget
knowledgebase  channels  automation  sla  ai  notifications
reporting  api  help
```

The `admin` module is a child module physically nested inside `agent` and resolves to `/agent/admin`. `help` was added with the extensibility work and ships first-party help content alongside the add-on contract.

## Features

### Ticketing core

- Full ticket lifecycle, status workflow, threading, merging, and linking, with a per-ticket event timeline owned by the `tickets` module.
- Internal notes are agent-only and never reach any client role, including an Organization Admin.
- Attachments persist through CBFS (local disk, AWS S3, or Backblaze B2) with configurable size and extension limits.
- Tickets can originate from unregistered senders. Such a ticket has no `Contact`, no `Organization`, and is visible only to provider agents until the agent promotes the sender into a `Contact`, at which point the ticket joins that organization's tenant scope.
- Per-organization custom fields, tags, and ticket-to-ticket links.

### Multi-tenant data isolation

- `Organization` is the tenant boundary. Single instance, single provider, one database, all client organizations as data within it.
- Every tenant-scoped table carries `organization_id` from its first migration. A Quick global scope defined in `contacts` enforces isolation on client-side queries automatically.
- The isolation is asymmetric by design: client users (`Contact` accounts on `/`) are hard-scoped to their own organization; provider agents (`Agent` accounts on `/agent`) see across all organizations, subject to their own RBAC.

### Channels intake

- Portal contact form on `/`, embeddable widget on `/widget`, and IMAP polling that turns inbound email into tickets (or appends to existing tickets via Message-Id threading).
- Address and domain blacklist checked on every inbound message before a ticket is created.
- Each channel normalizes through the `tickets` service layer, never by writing entities directly.

### SLA and business hours

- Per-organization SLA policies with first-response and resolution targets.
- Business-hours calendars carry their own time zone and honor holiday schedules.
- Pause and resume semantics for waiting-on-customer states; breach warnings via scheduled task.

### Automation

- Trigger-condition-action rules engine for routing, tagging, escalations, and assignment.
- Assignment strategies including round-robin and load-based.
- Recurring tickets for scheduled work.

### Knowledge base

- Versioned articles with draft and publish states, per-article feedback, and view analytics.
- Three-tier visibility: public, organization-scoped, and internal-agent-only.
- When AI is enabled, semantic search via pgvector cosine similarity, plus an agent button that drafts a KB article from a resolved ticket.

### Notifications fan-out

- Email, Slack or Microsoft Teams (both accept the Slack-compatible webhook payload), and in-app delivery.
- Unsubscribe tokens are HMAC-SHA256 signed and pinned to a specific `(recipient, event, channel)` tuple, so a leaked token cannot silence unrelated streams.
- Per-user delivery preferences with an outbound kill switch (`OUTBOUND_EMAIL_ENABLED=false`) for staging stacks pointed at production data.

### Auth and RBAC

- Local credentials only, through cbauth and cbSecurity, for both account families. There is no SSO.
- TOTP MFA is required for provider agent accounts and optional for client `Contact` accounts. Enabling TOTP issues one-time recovery codes.
- A provider admin has an MFA reset path in `/agent/admin` for users who lose both their device and their recovery codes.

### Admin

- `/agent/admin` is gated to high-privilege provider roles. Unauthorized direct access returns HTTP 403, not 404.
- The `admin` module is physically nested inside `agent` so its security travels with the module. It is still independently testable.

### Audit

- A cross-cutting `AuditEvent` log owned by the `audit` module records significant operations (SLA policy changes, contact merges, role assignments, article deletions, and similar) so an admin can search the history later.
- Distinct from the ticket-level event timeline, which the `tickets` module owns.

### REST API and widget

- Versioned API at `/api/v1`, JWT-authenticated through cbSecurity, with serialization through mementifier.
- OpenAPI documentation generated by cbswagger.
- The widget at `/widget` is served separately from the portal so it can be cached and rate-limited independently.

### Background work

- One cbq worker container processes AI calls, outbound email, webhook delivery, and report builds. Scalable with `docker compose up --scale worker=N` and no code change.
- ColdBox scheduled tasks handle time-based work: SLA breach checks, recurring tickets, scheduled report exports, and the nightly database backup that writes a compressed `pg_dump` to the configured CBFS provider with `BACKUP_RETENTION_DAYS` pruning.

### Add-on framework

- Third-party ColdBox modules ship into a TesseraBX deployment at `modules/` (ForgeBox install path) or in-tree under [`sample-addons/`](sample-addons/) for first-party demos.
- Add-ons declare contributions via a `settings.tesserabx` block in their `ModuleConfig`: navigation, admin pages, ticket panels, dashboard widgets, channel adapters, automation actions, AI features, API resources, webhook events, notification templates and channels, custom field types, audit event types, per-tenant settings, help pages, roles, and permissions.
- Live contract in [docs/EXTENSIONS.md](docs/EXTENSIONS.md); worked reference in [`sample-addons/example-sync/`](sample-addons/example-sync/).

### AI assist (optional)

When enabled, AI powers ticket triage, suggested agent replies, thread summaries, reply-tone review, KB article drafting from tickets, semantic KB suggestions, and escalation-risk scoring. With AI off, none of these features render anywhere in the UI. See the [AI integration](#ai-integration) section below for the full surface.

## Tech stack

- **Runtime**: BoxLang on the official BoxLang Docker image.
- **Framework**: ColdBox 8+.
- **UI**: CBWire for server-driven reactive components, AdminLTE 4 (Bootstrap 5) for the layout shell.
- **Database**: PostgreSQL 16 with the `pgvector` extension enabled (no separate vector store).
- **Cache and queue**: Redis (CacheBox provider; cbq queue backend).
- **Storage**: CBFS with three providers (local disk, AWS S3, Backblaze B2 or any S3-compatible endpoint).
- **AI (optional)**: `bx-ai` server module, accessed only through the `ai` middleware facade. OpenRouter is the documented default provider.

### Production dependencies (`box.json`)

| Module | Purpose |
| --- | --- |
| `coldbox` | MVC framework |
| `cbsecurity` | Authentication, authorization, JWT, security rules |
| `cbauth` | Auth provider |
| `cbvalidation` | Form and API payload validation |
| `cbmailservices` | Outbound email |
| `cbmessagebox` | Flash messaging |
| `cbstorages` | Session and request storage abstractions |
| `cbpaginator` | Pagination helper |
| `cbi18n` | Internationalization |
| `cbcsrf` | CSRF tokens |
| `cbantisamy` | HTML sanitization for rich-text input |
| `cbswagger` | OpenAPI generation from handler annotations |
| `cbq` | Background job queue |
| `cbfs` | File storage abstraction (local, S3, B2) |
| `cbwire` | Server-driven reactive UI |
| `cors` | CORS response headers |
| `cfmigrations` | Database schema versioning |
| `mementifier` | Quick entity to memento serialization |
| `qb` | SQL query builder |
| `quick` | ORM and entity relationships |
| `hyper` | HTTP client |
| `bcrypt` | Password hashing |
| `s3sdk` | AWS S3 client (used by CBFS S3 and B2 providers) |

### Dev-only dependencies (`box.json` `devDependencies`)

These are **not** installed in production deploys. CommandBox installs them only when `box install` is run without `--production`.

| Module | Purpose |
| --- | --- |
| `testbox` | BDD and unit test framework |
| `cbdebugger` | In-page debug overlay |
| `commandbox-dotenv` | `.env` loader for CommandBox tasks |
| `commandbox-cfformat` | Code formatter |
| `commandbox-cfconfig` | CommandBox server config tool |
| `commandbox-migrations` | Migration runner CLI |

## Quick Deploy

The shortest path to a running production stack on a fresh host. Read this section even if you intend to dive into [Running the production stack](#running-the-production-stack) below.

### 1. Prerequisites

- Docker Engine and the `docker compose` CLI plugin on the deploy host.
- An external Docker network already created and owned by your reverse proxy. Its name goes in `.env` under `PROXY_NETWORK`. The proxy itself owns TLS, HTTPS, and certificates; this stack speaks plain HTTP.

### 2. Clone and prepare `.env`

```bash
git clone https://github.com/oistechnologies/tesserabx.git /opt/tesserabx
cd /opt/tesserabx
cp .env.example .env
```

### 3. Edit the secrets and the proxy network

At a minimum, change these in `.env` before bringing the stack up:

- `PROXY_NETWORK` to the name of the external Docker network your reverse proxy already owns.
- `DB_PASSWORD` to a strong value.
- `JWT_SECRET` to a long random string (signs API access and refresh tokens). Leaving it blank lets cbSecurity auto-generate one that rotates on every restart, which invalidates every issued token. Fine for dev, never for production.
- `NOTIFICATIONS_UNSUBSCRIBE_SECRET` to a long random string (HMAC-SHA256 key for unsubscribe tokens).
- `APP_BASE_URL` to the public hostname agents and contacts reach the app at; it is used to build the unsubscribe links embedded in outbound email.
- `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM`, `MAIL_FROM_DOMAIN` to your outbound relay.
- `CBFS_DEFAULT_PROVIDER` to `s3` or `b2` for an offsite-capable backup target, and populate `CBFS_PROVIDER_*` with the credentials and bucket. Leaving it on `local` means the nightly backup lands on the same host as the database (see [Database backups](#database-backups)).

To enable AI from day one, set `AI_ENABLED=true` and populate `AI_API_KEY`, `AI_MODEL` (and optionally `AI_PROVIDER`, `AI_BASE_URL`). The full annotations for every variable live in [.env.example](.env.example).

### 4. Bring the stack up

```bash
docker compose up -d --build
```

Migrations apply automatically on the first boot of the `app` container via [docker/app-entrypoint.sh](docker/app-entrypoint.sh). The worker and scheduler containers wait on `app` healthcheck before starting.

### 5. Create the first provider agent (manual)

> **Important.** A fresh production deployment has no users. The seeder is dev-only and should not be run in production. Until an env-var-gated admin bootstrap lands (tracked as future work), the operator must seed the first agent by hand.

Two viable workarounds today:

- **Insert directly** into the `agents` table with a bcrypt-hashed password (use the `bcrypt` module's CLI or any standalone bcrypt utility to generate the hash). Set `is_admin = true` and an appropriate role so the new account can reach `/agent/admin`.
- **Run the dev seeder once** with `docker compose exec app box migrate seed run`, then immediately log in as the seeded `agent@example.com`, create your real agent account through `/agent/admin`, and delete the seeded accounts.

### 6. Verify it is live

- `GET /health` returns 200.
- Your first agent can log in at `/agent` and reach `/agent/admin`.
- Run the storage verification at `/agent/admin/storage` (see [Storage verification](#storage-verification-deployment-readiness-gate)) and confirm every step passes.
- Your reverse proxy routes `/`, `/agent`, `/api`, and `/widget` through to the `app` container on its internal port 8080.

## Running the dev stack

The development stack is self-contained: no reverse proxy, no external Docker network, no TLS, the application's HTTP port published directly to the host. It adds Mailpit (SMTP trap) and Adminer (database inspector) on top of the base stack.

```bash
cp .env.example .env
docker compose -f compose.yaml -f compose.dev.yaml up --build
```

Once everything is healthy:

| Surface       | URL                                 |
|---------------|-------------------------------------|
| Client portal | <http://localhost:8080/>            |
| Agent surface | <http://localhost:8080/agent>       |
| Admin surface | <http://localhost:8080/agent/admin> |
| REST API      | <http://localhost:8080/api/v1>      |
| Widget        | <http://localhost:8080/widget>      |
| Health check  | <http://localhost:8080/health>      |
| Mailpit UI    | <http://localhost:8025/>            |
| Adminer       | <http://localhost:8081/>            |

Migrations run automatically when the `app` container starts. Seed the two test accounts:

```bash
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
- A reverse proxy (Nginx, Traefik, Caddy, whatever you run) attached to that network, owning TLS, HTTPS, and certificates. The compose stack itself speaks plain HTTP; the proxy terminates TLS.
- A populated `.env` file in the project root (never committed). See `.env.example` for every variable.
- A plan for [the first-agent bootstrap](#5-create-the-first-provider-agent-manual), since the dev seeder is not appropriate for production.

### First-time deploy

See [Quick Deploy](#quick-deploy) above for the minimum five-step recipe. The additional considerations for a real production host are:

- Named volumes `db_data` and `redis_data` persist across `docker compose up --build`. Container rebuilds do not lose data, but a manual `docker volume rm` does.
- `depends_on: condition: service_healthy` makes the worker and scheduler wait for the new `app` to be healthy before swapping in.
- Scale the worker pool with `docker compose up -d --scale worker=N` once the baseline is in place. The scheduler is intended as a single replica.

### Updating an existing deploy

```bash
cd /opt/tesserabx
git pull
docker compose up -d --build
```

`docker compose up --build` re-runs the Dockerfile from the new working tree. Containers are rebuilt and recreated; the named volumes (`db_data`, `redis_data`) persist across this. Migrations run automatically on the new `app` container at start.

### What the proxy must route to `app:8080`

The four path groups are served by the same `app` container; route everything that starts with these to it:

- `/` to the client portal surface
- `/agent` to the technician dashboard, with `/agent/admin` nested inside
- `/api` to the versioned REST API
- `/widget` to the embeddable widget intake

The proxy is also responsible for forwarding the usual headers (`X-Forwarded-For`, `X-Forwarded-Proto`, `Host`) so the application sees the correct client address and original protocol.

### Things that are NOT in scope for this manual flow

These are tracked as Phase 6 hardening; the manual recipe above is what ships until then.

- Automated CD (no git-push triggered deploys; no GitHub Actions deploy job).
- Image registry. There is no `docker push` step. The image stays local to each deploy host.
- Rollback automation. Roll back by `git checkout <previous-sha> && docker compose up -d --build`.
- Pre-deploy database backups. Run `pg_dump` manually before a risky migration until the nightly backup task is fully in place.
- Zero-downtime restarts and blue/green. Compose stops the old container before starting the new one; expect a short cutover window.
- Secrets management beyond `.env`. The `.env` file on the host is the single source.
- An env-var-gated admin bootstrap for the first provider agent. Until it lands, see [Quick Deploy step 5](#5-create-the-first-provider-agent-manual).

## Storage providers

Three CBFS providers ship, picked one per environment with `CBFS_DEFAULT_PROVIDER`:

- `local` is disk on the running container. Development default. Files persist to `/storage` inside the container.
- `s3` is genuine AWS S3 via cbfs's stock S3Provider. Pointed at `amazonaws.com` with `CBFS_PROVIDER_REGION` as the AWS region.
- `b2` is Backblaze B2 (or any other S3-compatible endpoint whose hostname embeds the region, such as Wasabi, DigitalOcean Spaces, MinIO, etc.) via [B2Provider@core](modules_app/core/models/cbfs/B2Provider.cfc). The patched provider swaps in [PatchedAmazonS3.cfc](modules_app/core/models/cbfs/PatchedAmazonS3.cfc) which corrects s3sdk's path-style URL builder for non-AWS domains; talking to a B2 bucket through the stock provider produces a doubled region in the hostname and a 403 on every request.

`s3` and `b2` share one set of credential env vars (`CBFS_PROVIDER_ACCESS_KEY`, `CBFS_PROVIDER_SECRET_KEY`, `CBFS_PROVIDER_BUCKET`, `CBFS_PROVIDER_REGION`, `CBFS_PROVIDER_ENDPOINT`) since only one is active per environment. `CBFS_PROVIDER_ENDPOINT` is only consulted by the `b2` provider; `s3` always talks to `amazonaws.com`.

A separate public disk (`CBFS_PUBLIC_PROVIDER`) handles files served directly to the browser without an app round-trip (agent avatars, public KB downloads). The default `public-local` serves them out of `/app/public-files` at `/public-files/...`; `public-s3` and `public-b2` write with `defaultACL=public-read` to a world-readable bucket whose URL `CBFS_PUBLIC_BASE_URL` points at.

## Storage verification (deployment-readiness gate)

Before the first production deploy, log in as an admin agent and visit `/agent/admin/storage`. The "Run verification" button drives a five-step smoke test against the active CBFS provider:

1. **write** writes 4 KB of random bytes to `storage-verify/test-<uuid>.bin`.
2. **read-back** fetches the bytes and SHA-256 compares end to end.
3. **signed-url** requests a time-limited signed URL and confirms a real HTTP GET returns 200 (S3 family only; skipped on local disk).
4. **private-bucket** requests the bucket's public URL and confirms it rejects with 401 or 403 (skipped on local; if it returns 200, the bucket is public, so tighten the ACL before going live).
5. **delete** removes the test object.

Every step must be green before declaring the storage path production-ready. The verification is safe to re-run any time; the test object lives under `storage-verify/` and is removed on success.

## Database backups

A nightly database backup task runs `pg_dump`, compresses the dump, and writes it to the configured CBFS provider under a dated path. It prunes dumps older than `BACKUP_RETENTION_DAYS`.

> **Warning.** When `CBFS_DEFAULT_PROVIDER=local` in production, the backup file lands on the same host as the database. That is only partial protection; if the host fails, both the database and its backups are lost together. Setting `CBFS_DEFAULT_PROVIDER=b2` (with Backblaze B2 credentials populated) or `CBFS_DEFAULT_PROVIDER=s3` (for genuine AWS S3) places backups offsite and negates that concern. Disaster recovery beyond nightly backups (point-in-time recovery, tested restores, replication) is the operator's responsibility.

## AI integration

TesseraBX is fully functional with no AI configuration. When `AI_ENABLED=false` (the default in [.env.example](.env.example)), the entire AI layer is inert: no AI UI elements render anywhere, no AI cbq paths run, no AI interceptors fire, and every AI call site takes the non-AI branch. The `ai` module is the only code in the repository that imports `bx-ai`; every other module reaches AI through the middleware facade.

### What AI does when enabled

| Feature | Where it surfaces | Service |
| --- | --- | --- |
| Ticket triage | Interceptor on ticket creation; sets priority, type, tags, and sentiment | [TriageService](modules_app/ai/models/TriageService.bx) via [TriageInterceptor](modules_app/ai/interceptors/TriageInterceptor.bx) |
| Suggested reply | Agent button on ticket detail | [SuggestedReplyService](modules_app/ai/models/SuggestedReplyService.bx) |
| Thread summary | Collapse-long-threads button on ticket detail | [SummarizationService](modules_app/ai/models/SummarizationService.bx) |
| Reply-tone review | Pre-send check on outgoing agent replies | [ReplyToneService](modules_app/ai/models/ReplyToneService.bx) |
| KB draft from ticket | Agent button on a resolved ticket; produces a draft KB article | [KbDraftService](modules_app/ai/models/KbDraftService.bx) |
| Related-article suggestions | Ticket detail panel and portal contact form; semantic KB search via pgvector cosine similarity | [KbSuggestionService](modules_app/ai/models/KbSuggestionService.bx) |
| Escalation-risk scoring | Interceptor on ticket creation and status change | [EscalationRiskService](modules_app/ai/models/EscalationRiskService.bx) |

### The middleware facade

Every AI call routes through [AiMiddleware](modules_app/ai/models/AiMiddleware.bx), which enforces:

- The master capability flag ([AiCapability](modules_app/ai/models/AiCapability.bx) reads `AI_ENABLED` plus per-feature enable checks).
- Pre-flight PII redaction (email masking by default, controlled by `AI_PII_REDACTION`; phone numbers and credit-card-shaped digit runs are on the roadmap).
- Per-call timeouts (`AI_TIMEOUT_SECONDS`); a timeout records a `timeout` outcome in `ai_interactions` without breaking the caller's flow.
- Outcome envelopes returned to every caller: `ok`, `disabled`, `redacted_only`, `error`, or `not_implemented`. Callers branch on the outcome and fall back gracefully when AI is off or unavailable.
- Logging of every interaction to the `ai_interactions` table so an admin can audit costs, latency, and outcomes.

### pgvector and embeddings

- KB articles store a `vector(1536)` column. The dimension is fixed by the column type; changing models to a different dimension requires altering the column.
- Embeddings are written on KB publish via [KbIndexingInterceptor](modules_app/ai/interceptors/KbIndexingInterceptor.bx) and backfilled in batches of 25 by [EmbeddingScheduler](modules_app/ai/models/EmbeddingScheduler.bx) for any article missing a vector.
- Add-ons can register their own embedding-consumer entities via [EmbeddingConsumerRegistry](modules_app/ai/models/EmbeddingConsumerRegistry.bx); the first-party `help` module does exactly this so help pages participate in semantic search.

### Add-on AI gating

Four UI registries check the same `aiEnabled` flag and silently drop entries with `requiresAi : true` when AI is off, so a missing check cannot leak a half-rendered AI control:

- [NavigationRegistry](modules_app/core/models/NavigationRegistry.bx) (sidebar navigation entries)
- [AdminPagesRegistry](modules_app/agent/modules/admin/models/AdminPagesRegistry.bx) (admin-area pages)
- [TicketPanelRegistry](modules_app/tickets/models/TicketPanelRegistry.bx) (ticket detail panels: summary, escalation-risk, kb-draft, related-articles)
- [DashboardWidgetRegistry](modules_app/reporting/models/DashboardWidgetRegistry.bx) (dashboard widgets, including the agent-home AI activity card)

Add-ons declaring `requiresAi : true` in their `settings.tesserabx` block participate in the same gating without writing the check themselves.

### Environment variables

| Variable | Purpose |
| --- | --- |
| `AI_ENABLED` | Master on/off (default `false`) |
| `AI_PROVIDER` | Provider name; documented default is `openrouter` |
| `AI_API_KEY` | Provider credential |
| `AI_MODEL` | Chat model identifier (e.g., `openai/gpt-4o`) |
| `AI_BASE_URL` | Optional, for a custom or self-hosted OpenAI-compatible endpoint |
| `AI_TIMEOUT_SECONDS` | Per-call timeout (default 60) |
| `AI_PII_REDACTION` | Email masking pre-flight (default `true`) |
| `AI_EMBEDDING_MODEL` | Embeddings model (default `openai/text-embedding-3-small`) |
| `AI_EMBEDDING_DIM` | Embedding dimension; must match the `vector(N)` column type (default 1536) |

Full annotations are in [.env.example](.env.example).

## Extensibility

TesseraBX is built to accept third-party ColdBox modules as add-ons. An add-on ships at `modules/` (standard ForgeBox install path) or in-tree under [`sample-addons/`](sample-addons/) and declares its contributions in a `settings.tesserabx` block inside its `ModuleConfig`. The contract covers navigation entries, admin pages, ticket panels, dashboard widgets, channel adapters, automation actions, AI features, API resources, webhook events, notification templates and channels, custom field types, audit event types, per-tenant settings, help pages, roles, and permissions.

Hard constraints still apply to add-ons. Every add-on entity table needs `organization_id`. AI-requiring contributions are centrally hidden when `AI_ENABLED=false`. Add-ons reach other modules through their service layers, never by importing entities directly.

The live contract is in [docs/EXTENSIONS.md](docs/EXTENSIONS.md). A worked reference add-on lives at [`sample-addons/example-sync/`](sample-addons/example-sync/) and exercises every contribution type.

## Repository layout

```text
Application.cfc              ColdBox bootstrap
index.cfm                    front-controller placeholder (ColdBox 8 convention)
box.json                     CommandBox + dependency manifest
server.json                  CommandBox server config; declares BoxLang modules
config/                      ColdBox / CacheBox / WireBox / Router / Scheduler
config/boxlang.json          BoxLang runtime config and datasource definition
handlers/                    root-level handlers (Main)
includes/helpers/            ApplicationHelper.cfm and friends
layouts/                     reserved for root-level layouts (rare)
modules_app/                 the seventeen app-owned modules live here
modules/                     CommandBox-installed third-party modules (gitignored)
sample-addons/               first-party reference add-ons (in-tree, not gitignored)
resources/database/migrations  cfmigrations migration files
resources/database/seeds       development seeders
resources/tasks/             worker and scheduler entrypoint tasks
docker/                      worker and scheduler entrypoint shell scripts
docs/                        durable specs (BUILD-PLAN, EXTENSIBILITY-PLAN, EXTENSIONS)
tests/                       TestBox runner and top-level specs
```

## Running tests

```bash
docker compose exec app box migrate up
docker compose exec app box testbox run
```

CI runs the same TestBox specs on a disposable PostgreSQL container (with `pgvector`) and Redis on every push to `main` and every pull request.

## Current state

Phase 0 (scaffolding, dev stack, both surfaces, both account families, base RBAC, the `/agent/admin` 403 rule, CI) is complete. Active work is in the extensibility track: the four UI registries, the add-on manifest contract, dashboard widgets contributed by add-ons, and the first-party `help` module.

For live phase status, read [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md) and [docs/EXTENSIBILITY-PLAN.md](docs/EXTENSIBILITY-PLAN.md). For the durable architectural constraints that hold across every phase, read [CLAUDE.md](CLAUDE.md).
