# TesseraBX

TesseraBX is a full-featured help-desk and customer support platform. It is a ColdBox application running on the BoxLang runtime, deployed via Docker, with optional AI integration through the `bx-ai` BoxLang server module.

This file is the durable specification for the project. It is the set of constraints, conventions, and architectural rules that must hold across the entire build. Read it at the start of every working session and consult it whenever a decision touches architecture, module boundaries, tenancy, or the technology stack. The phased build order and per-phase deliverables live separately in `docs/BUILD-PLAN.md`; this file is the "what must always be true," the build plan is the "what to do next."

When this file and any other instruction conflict, this file wins unless the human explicitly overrides it in the conversation.

---

## What this project is

One help-desk provider company runs TesseraBX and uses it to provide support services to multiple client companies. Each client company is an `Organization`. Client users submit and track support requests through a self-service portal, an embeddable widget, or email. The provider's own agents and technicians work tickets through a separate dashboard. The system automates triage, routing, and SLA enforcement, and when AI is configured it assists agents and deflects common questions.

It is a single application composed of many independently testable ColdBox modules. It runs as a Docker stack, with a separate development stack that adds mail trapping and developer tooling.

---

## Hard constraints

These are not preferences. Do not violate them, and do not "improve" the architecture by working around them. If one of these appears to block progress, stop and raise it with the human rather than routing around it.

### Entity ownership

- **Each module owns the Quick entities for its own domain.** There is no shared `domain` module and one must never be created.
- **Cross-module data access goes through the owning module's service layer.** A module never imports or directly instantiates another module's entities. A handler in `reporting` does not `new`-up a `Ticket`; it asks the `tickets` service.
- **Cross-module Quick relationships are allowed** (a `Ticket` may `belongsTo` a `Contact`), but the **module dependency graph must stay acyclic**. Module load order follows the dependency direction. No two modules may circular-depend. If a relationship would create a cycle, the lower-level module defines the relationship and the higher-level module reaches in through the service layer.
- **`contacts` is the foundational module.** It owns the tenant-boundary entities (`Organization`, `Office`, `Contact`) and depends on nothing below it. Most other modules depend on `contacts`.
- **`audit` is a low-level module.** It owns the central `AuditEvent` entity and sits near the bottom of the dependency graph, because many modules write to it. It is distinct from any module's own domain history (for example `tickets` owns `TicketEvent` for the agent-facing ticket timeline; that is a separate thing from the cross-cutting compliance log in `audit`).

### Tenancy and data isolation

- **`Organization` is the tenant boundary.** There is no tenant entity above it. This is a single-instance, single-provider deployment: one database, one schema, all client organizations as data within it.
- **Row-scoped shared schema.** Every tenant-scoped table carries an `organization_id`. Isolation is enforced in the application layer through a Quick global scope (or shared base entity) that automatically filters client-side queries to the requesting user's organization.
- **The tenant scope is designed in from the first migration.** Every tenant-scoped entity gets the `organization_id` column and the scope from day one. It is never retrofitted.
- **The isolation primitive lives in `contacts`.** The base entity or reusable Quick scope that enforces tenancy lives in the `contacts` module, alongside the tenant entities. Tenant-scoped entities in other modules apply it.
- **Client-side visibility is asymmetric from provider-side.** Client users (`Contact` accounts, the `/` surface) are hard-scoped to their own organization. Provider users (`Agent` accounts, the `/agent` surface) see across all organizations, subject to their own RBAC. The Quick global scope and cbSecurity firewall behave differently per surface, and that difference is intentional.
- **Internal notes never reach any client-side role.** `TicketMessage` records flagged internal are agent-only. No client role, including Organization Admin, ever exposes them.
- **Tickets can exist without a `Contact`.** A ticket may originate from an unregistered sender, identified only by a raw email address with no `Contact` and therefore no `Organization`. Such a ticket has no `organization_id`, sits outside the tenant scope, and is visible only to provider agents, never to any client user. A provider agent can promote the sender into a real `Contact` (the agent-created provisioning path), which assigns the ticket into an organization and brings it under the tenant scope. The data model, the tenant scope, and the agent UI must all accommodate this accountless state from the start; it is not an edge case bolted on later.
- **Schema-per-tenant and database-per-tenant are rejected.** Do not propose or implement them.

### AI is strictly optional

- **The system must be fully functional with no AI configuration provided.** AI is an enhancement, never a dependency.
- **When AI is not configured, no AI-related UI is displayed anywhere** — no suggested-reply panels, no triage badges, no AI assistant, no summarize buttons. Every AI-related CBWire component and view partial checks the capability flag and renders nothing when AI is off. This is enforced at the layout and component level so a missing check cannot leak a half-rendered control.
- **The `ai` module is the only code that imports `bx-ai`.** Every AI feature calls the AI middleware facade, never the provider directly.
- **Feature modules treat AI as an optional collaborator.** If the capability flag is off, the AI call site is skipped and the non-AI path proceeds. cbq jobs for AI work are only enqueued when AI is enabled.

### Surfaces and routing

- **Two surfaces, each a genuinely separate shell** with its own ColdBox layout, its own navigation, and its own cbSecurity firewall configuration.
  - `/` — the client portal, served by `portal`.
  - `/agent` — the technician dashboard, served by `agent`.
- **`/api`** is the versioned REST API, served by `api`. **`/widget`** is the embeddable widget intake, served by `widget`.
- **Admin is not a third surface.** The `admin` module is a child module physically nested inside `agent` (in `agent`'s own `modules` folder). It loads as part of `agent`'s lifecycle and resolves to `/agent/admin` through the parent entry point. It ships its own module-level cbSecurity rules covering `/agent/admin/*`, gated to high-privilege roles, so the security travels with the module. It remains independently testable.
- **Unauthorized direct access to `/agent/admin` returns 403**, not 404. The route exists; access is denied.
- All four path groups are served by the one `app` container. No subdomain split.

### Authentication

- **All authentication is local credentials** through cbSecurity and cbauth, for both account families (client `Contact` accounts and provider `Agent` accounts). **There is no SSO.** SSO (OIDC or SAML) is a deferred future addition and must not be improvised into the build.
- **MFA is TOTP-based** (RFC 6238: QR-code enrollment into an authenticator app, rotating six-digit codes, no SMS).
- **MFA is optional for client users and required for provider agents.** A client user may enable MFA on their own account; a provider agent account must have it, because agent accounts see across all client organizations.
- Enabling TOTP issues one-time **recovery codes**. A provider admin has an **MFA reset path** in `/agent/admin` for users who lose both their device and their recovery codes.
- MFA is built in Phase 6; the rest of the authentication model (local credentials, the two account families, the firewall per surface) is established in Phase 0.

### Deliverable content rules

- **Never use em dashes in generated or rewritten content, code comments intended as deliverables, documentation, or any project artifact.** Use commas, parentheses, or restructured sentences instead. This applies to everything written into the repository.

---

## Technology stack

This is settled. Do not substitute components without an explicit instruction from the human.

### Runtime and framework

- **BoxLang** runtime, using the **official BoxLang Docker image** as the base for all application containers.
- **ColdBox 8+** as the MVC framework.
- **CommandBox** for dependency management and task runners, layered on the official BoxLang image.
- **CBWire** for the reactive, server-driven UI.
- **bx-ai** for AI provider access (optional at runtime).

### Ortus and ColdBox modules

- **cbSecurity** (on **cbauth**) for authentication and authorization: security rules, JWT for the API, annotation-driven handler security.
- **qb** for the query builder across all dynamic SQL.
- **quick** for ORM and entity relationships.
- **cbvalidation** for all inbound validation (form posts and API payloads).
- **cbmailservices** for outbound mail; the integration point for the development mail trap.
- **cfmigrations** for schema versioning and repeatable database builds.
- **mementifier** for serializing Quick entities to mementos, used heavily by `api`.
- **cbq** for background job processing: async AI calls, email sending, webhook delivery, report generation.
- **cbswagger** to auto-generate OpenAPI docs from the `api` handlers.
- **CBFS** for all file persistence: attachments, generated reports, exports.
- **TestBox** for unit, integration, and BDD specs.
- **cbdebugger** in the development stack only.

### Data and infrastructure

- **PostgreSQL 16** as the database, with the **`pgvector`** extension enabled. `pgvector` handles vector similarity search natively, so there is no separate vector-store service.
- **Redis** for caching (CacheBox provider) and as the cbq queue backend.
- **No reverse proxy in the stack.** An external reverse proxy is assumed. Containers attach to an external Docker network whose name comes from `PROXY_NETWORK` in `.env`. TLS, HTTPS, and certificates are the external proxy's responsibility.
- **CBFS storage** with two providers: a local disk provider (the default for development) and an S3-compatible provider. **Backblaze B2** is the S3-compatible target for shared, staging, and production environments. Buckets are private; files are served via time-limited signed URLs, with app-streaming behind cbSecurity as the documented fallback.
- **Mailpit** as the development-only mail trap.
- **AdminLTE 4** (Bootstrap 5) as the UI theme foundation for both surface layouts.

### UI

- **CBWire-first.** Reactive components for queues, ticket lists, dashboards, filters, and forms. State and logic stay in CFML on the server.
- **Per-screen fallback** to the conventional ColdBox handler-plus-view template model is allowed where CBWire proves troublesome for a specific screen. The fallback is the exception, decided per screen, never an all-or-nothing switch.
- **AdminLTE 4** provides the dashboard shell, navigation, cards, and widget layouts. Each surface gets its own AdminLTE-based layout; shared CBWire components and styling conventions are used across both where it makes sense.
- Charts use a Bootstrap 5-compatible library (Chart.js or similar).

---

## Modules

Seventeen custom modules. Each owns its routes, handlers, models (including its own Quick entities), views, CBWire components, config, and specs.

| Module | Owns | Responsibility |
|---|---|---|
| `core` | nothing | App shell: AdminLTE layouts for both surfaces, shared CBWire components and conventions, base handler, shared interceptors, global config, health-check endpoints. |
| `contacts` | `Organization`, `Office`, `Contact`, org domain mappings, the tenant isolation primitive | **Foundational module.** Contacts and organizations, offices, company grouping with domain mapping, merge, tiers, per-organization custom fields, client-side roles. Owns the tenant-boundary entities and the Quick global scope that enforces isolation. |
| `audit` | `AuditEvent` | **Low-level module.** The central cross-cutting audit log: a service layer other modules call to record significant operations (SLA policy changes, contact merges, role assignments, article deletions, and similar), plus the admin-facing reporting and search UI for those events. Distinct from `tickets`'s own `TicketEvent` timeline. Built to be extended with new event types over time. |
| `tickets` | `Ticket`, `TicketMessage`, `TicketEvent`, `TicketLink`, `Attachment`, `Tag`, custom-field entities | Ticketing core: lifecycle, status workflow, threading, merging, linking, assignment, audit trail, attachments, custom fields. Supports tickets from unregistered senders (no `Contact`, no organization scope until promoted). |
| `agent` | `Agent`, `Team`, agent-local entities (e.g. saved filters) | Technician dashboard, serves `/agent`: queues, saved filters, bulk actions, canned responses, collision detection, internal mentions, time tracking. Contains the nested `admin` child module. |
| `admin` | RBAC, branding, and configuration entities | Administration and configuration: RBAC management, teams and groups, custom field and form builder, branding, email server settings, the inbound blacklist management UI, admin audit log views. Nested inside `agent`, resolves to `/agent/admin`. |
| `portal` | nothing of its own | Customer-facing self-service, serves the root (`/`) surface: ticket submission and tracking, guest submission with email verification. |
| `widget` | nothing of its own | Embeddable support widget intake and its public endpoints. Separate from `portal` so it can be cached and rate-limited independently. |
| `knowledgebase` | `Article`, `ArticleVersion`, `ArticleFeedback`, `Category`, `ArticleOrganization` | Article authoring, versioning, draft/publish, categories, feedback, view analytics, three-tier visibility (public, organization-scoped, internal). |
| `channels` | channel-config entities, the inbound blacklist entities | Channel intake and normalization: inbound email parsing, live chat, contact form. Each channel normalizes into the ticket model by calling the `tickets` service layer. Owns the email-address and domain blacklist, checked on every inbound message before a ticket is created. |
| `automation` | `AutomationRule` and related config entities | Rules engine: trigger-condition-action automations, escalation rules, assignment strategies (round-robin, load-based), recurring tickets. |
| `sla` | `SlaPolicy`, `BusinessHoursCalendar`, related entities | SLA policies, business-hours calendars, holiday schedules, first-response and resolution targets, breach warnings, pause and resume. |
| `ai` | `AiInteraction` | bx-ai integration plus the AI middleware facade (logging, PII redaction, rate limiting, provider abstraction, the capability flag). Optional at runtime. |
| `notifications` | notification templates, delivery-preference entities | Outbound notification fan-out: email, Slack or Teams, in-app. Consumes events announced by other modules. |
| `reporting` | nothing | Dashboards, ticket and agent metrics, SLA compliance, channel breakdown, backlog aging, scheduled exports, raw data export. Reads across other modules' service layers. |
| `api` | nothing of its own | Versioned REST API, JWT auth, serialization through mementifier, OpenAPI docs through cbswagger, webhook dispatch. Serializes entities owned by other modules. |

Dependency rules:

- `contacts` sits at the bottom of the graph and depends on nothing below it.
- `audit` is also a low-level module; many modules depend on it to record events. It depends on nothing that would create a cycle.
- `tickets`, `sla`, `automation`, `knowledgebase`, `reporting`, and `agent` depend on `contacts`.
- `channels`, `portal`, and `widget` create tickets through the `tickets` service layer, never by writing entities directly.
- `ai` is reached only through its middleware facade; feature modules depend on the facade interface, not on `bx-ai`.
- `notifications` is an event consumer; other modules announce events and `notifications` decides delivery.
- `admin` loads as part of `agent`'s lifecycle and reaches other modules' entities through their service layers.

---

## Conventions

### Namespacing

- The module namespace root is the full product name: `tesserabx.modules.tickets`, `tesserabx.modules.contacts`, and so on.
- The repository is `tesserabx`. The `box.json` slug, Docker image names, and other identifiers use `tesserabx`.

### Module structure

Every module follows the same internal layout: handlers, models (including its owned Quick entities and its service layer), views, CBWire components, config, a nested `modules` folder where applicable (as `agent` has for `admin`), and a `tests` folder with specs.

### Configuration

- **Environment variables only. No secrets in source.** A committed `.env.example` documents every variable, including:
  - `PROXY_NETWORK` — the external Docker network name.
  - PostgreSQL credentials and connection.
  - Redis connection.
  - The CBFS provider selection, plus Backblaze B2 credentials.
  - File upload constraints: a maximum file size and an allowed file-type list, both configurable.
  - Database backup retention: how many days (or how many dumps) of backups to keep before the backup task prunes older ones.
  - The AI provider config: provider, credentials, model, with OpenRouter as the documented default.
  - Mail settings.
- Config is loaded with `commandbox-dotenv` or equivalent.

### Time zones

- **Store all timestamps in UTC.** Display them in the viewing user's time zone.
- Business-hours calendars in `sla` carry their own time zone; SLA target calculation runs against the calendar's zone.
- Scheduled tasks and reporting are time-zone aware. This is a cross-cutting convention, not a per-module choice.

### File uploads

- Every upload through CBFS is constrained by a configurable maximum file size and a configurable allowed file-type list (see the `.env` variables above).
- Malware scanning is not in the initial scope; it is recorded as a deferred decision in the build plan.

### Database

- **`cfmigrations`** for all schema. Every tenant-scoped entity gets `organization_id` and the tenant scope in its very first migration.
- A **seeder task** provides development data: sample organizations, offices, contacts, tickets, articles, agents.

### Background work

- A single **cbq worker** container processes AI calls, outbound email, webhook delivery, and report builds. It is one replica by default but the image and compose definition are written so it scales with `docker compose up --scale worker=N` and no code change.
- **ColdBox scheduled tasks** handle time-based work: SLA breach checks, recurring tickets, scheduled report exports, data retention sweeps, and the nightly database backup.
- **Database backup** is a scheduled task (a `core`/scheduler concern, not a module of its own). Nightly, it runs `pg_dump`, compresses the dump, and writes it to the configured CBFS provider under a dated path (for example `backups/2026-05-14-….dump.gz`). It prunes dumps older than the configured retention. The backup target is whatever CBFS provider the environment uses: local disk in development, Backblaze B2 in production. The top-level README must carry a warning that if the production CBFS provider is the local disk provider, the backup lands on the same host as the database and is only partial protection, and that using the Backblaze or S3 provider in production places backups offsite and negates that concern. Running `pg_dump` requires the PostgreSQL client tools in the relevant container image.

### Source control and CI

- The project is a **GitHub** repository. CI runs on **GitHub Actions**, executing TestBox specs against a disposable PostgreSQL container (with `pgvector`) and Redis.

### Testing

- Unit specs for model services, dependencies mocked through MockBox.
- Integration specs for handlers and persistence, against a real PostgreSQL container with `pgvector`.
- API specs exercising `api` end to end, including JWT auth.
- CBWire component specs covering state transitions and rendering.
- Email assertions through the Mailpit JSON API.
- Storage specs using the local disk CBFS provider in CI, so tests do not depend on Backblaze.
- Security specs for cbSecurity rules.
- AI middleware specs with provider calls mocked, asserting redaction, logging, rate limiting, and the capability-flag behavior (including that AI UI is absent when AI is disabled).

### Documentation

- Each module carries a short README describing its responsibility, the entities it owns, its public service interface, and its events.
- The top-level README documents the external reverse-proxy expectation and the `PROXY_NETWORK` variable, and what the proxy needs in order to route to `app`.

### Code style

- Follow established CFML and ColdBox conventions.
- Remember the deliverable content rule above: no em dashes in anything written into the repository.

---

## Docker topology

### Base stack (`compose.yaml`)

- **app** — official BoxLang image with the ColdBox application.
- **worker** — same image as `app`, scheduler different entrypoint; the single cbq worker.
- **scheduler** — the `app` image with a scheduler entrypoint, running ColdBox scheduled tasks.
- **db** — PostgreSQL 16 with `pgvector`.
- **redis** — cache and cbq queue backend.

No `proxy` service and no vector-store service. `app` attaches to the external Docker network named by `PROXY_NETWORK`. Health-check endpoints on `app` and `worker`. Structured JSON logging through LogBox.

### Development stack (`compose.dev.yaml` override)

Runs standalone with no reverse proxy and no external network. `app` publishes its HTTP port directly to the host. Adds **mailpit** (SMTP trap, `cbmailservices` points at `mailpit:1025` in dev), **adminer** for database inspection, source mounted into `app` and `worker` for live reload, `cbdebugger` enabled, verbose logging.

`docker compose -f compose.yaml -f compose.dev.yaml up` gives a complete local environment with no proxy, no external network, no TLS. Production uses `compose.yaml` alone, attached to the existing proxy's network.

---

## How to use this with the build plan

`docs/BUILD-PLAN.md` defines the phased build order: Phase 0 scaffolding through Phase 6 integrations and hardening. Work through it in order. Each phase has concrete deliverables and an exit condition.

At every phase, the constraints in this file still apply. The build plan tells you what to build next; this file tells you what must remain true while you build it. When the two seem to disagree, this file governs and the disagreement is worth raising with the human.
