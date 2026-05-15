# TesseraBX Build Plan

This document is the phased build order for TesseraBX. It is meant to be worked through in sequence, Phase 0 first. Each phase lists concrete deliverables and an exit condition that must be met before moving to the next phase.

This file is the "what to do next." The companion file `CLAUDE.md` at the repository root is the "what must always be true" — the hard constraints, technology stack, module list, and conventions. Read `CLAUDE.md` first and keep its constraints in force through every phase. Where this plan and `CLAUDE.md` appear to disagree, `CLAUDE.md` governs; raise the disagreement with the human.

A note on content: do not use em dashes in anything written into the repository, including code comments meant as documentation, README files, and migration notes. This plan itself follows that rule.

---

## Working approach

- **Build in vertical slices.** Each phase should leave the application runnable, not half-wired. Prefer a thin feature that works end to end over a broad feature that is half-built across many modules.
- **Migrations are append-only and ordered.** Every tenant-scoped table gets `organization_id` and the tenant scope in the same migration that creates it. Never retrofit tenancy.
- **Specs accompany the code that they test**, in the same phase, in the owning module's `tests` folder. A phase is not complete if its deliverables are untested.
- **Stop and ask** when a decision is genuinely ambiguous or when a constraint in `CLAUDE.md` appears to block progress. Do not route around a hard constraint.
- **Commit per coherent unit of work** with clear messages, so the history reads as a sequence of intentional steps.

---

## Phase 0 — Scaffolding

Goal: an empty repository becomes a runnable, tested, deployable skeleton with every module present (empty but wired) and both Docker stacks working.

This phase assumes a bare, empty repository named `tesserabx` has been created and cloned. Everything else is built here.

### Deliverables

- **Project skeleton**: a ColdBox 8+ application on the BoxLang runtime, `box.json` with slug `tesserabx`, CommandBox-managed dependencies for every module listed in `CLAUDE.md`.
- **All seventeen module skeletons** created and registered: `core`, `contacts`, `audit`, `tickets`, `agent`, `portal`, `widget`, `knowledgebase`, `channels`, `automation`, `sla`, `ai`, `notifications`, `reporting`, `api`, plus `admin` nested inside `agent` as its child module. Each is empty but has the standard internal structure (handlers, models, views, CBWire components, config, `tests`) and the namespace root `tesserabx.modules.*`. Modules do nothing yet but load cleanly in dependency order.
- **Two surface layouts** wired: the `/` client portal shell and the `/agent` technician dashboard shell, each its own AdminLTE 4 (Bootstrap 5) layout with its own navigation placeholder and its own cbSecurity firewall configuration. CBWire installed and confirmed working with a trivial reactive component on each surface.
- **`admin` nested module** resolving at `/agent/admin`, with its own module-level cbSecurity rules covering `/agent/admin/*`, returning 403 on unauthorized direct access.
- **CBFS configured** with both providers: local disk (the development default) and the S3-compatible provider. Backblaze B2 credentials are read from `.env`; the provider is selectable by environment variable. No feature uses it yet, but the configuration is in place and a trivial round-trip (write a file, read it back) works on the local disk provider. File upload constraints (maximum file size, allowed file-type list) are wired as `.env`-driven settings now, even though no upload UI exists yet.
- **PostgreSQL 16 with `pgvector`**: the `db` container runs Postgres 16, the `pgvector` extension is enabled, and `cfmigrations` is initialized with a baseline migration. The extension being enabled does not mean anything uses it yet. The relevant container image includes the PostgreSQL client tools, so `pg_dump` is available for the backup task built in a later phase.
- **Redis** running and wired as the CacheBox provider and the cbq queue backend. cbq installed; the worker entrypoint exists and starts cleanly even though no jobs are defined yet.
- **Base authentication and RBAC** through cbSecurity and cbauth: the two account families (`Contact`-type client users and `Agent`-type provider users) can authenticate, and the firewall correctly routes each family to its surface. A minimal role system exists on each side. No real users or features yet, but login works and the surfaces are correctly gated.
- **Both Docker stacks**:
  - `compose.yaml`: `app`, `worker`, `scheduler`, `db`, `redis`. `app` attaches to the external network named by `PROXY_NETWORK`. No proxy service, no vector-store service.
  - `compose.dev.yaml`: runs standalone, no external network, `app` publishes its port to the host, adds `mailpit` and `adminer`, source mounted for live reload, `cbdebugger` enabled.
  - `docker compose -f compose.yaml -f compose.dev.yaml up` brings up a complete working local environment.
- **Health-check endpoints** on `app` and `worker`.
- **`.env.example`** committed, documenting every variable: `PROXY_NETWORK`, PostgreSQL credentials, CBFS provider selection and Backblaze credentials, file upload constraints (max size, allowed types), database backup retention, AI provider config (provider, credentials, model, with OpenRouter as the documented default), Redis connection, mail settings.
- **GitHub Actions CI**: runs TestBox specs against a disposable PostgreSQL container (with `pgvector`) and Redis. Green on an empty but correctly wired project.
- **Top-level README**: how to run the dev stack, the external reverse-proxy expectation, what the proxy must route to `app` (the `/`, `/agent`, `/api`, `/widget` path groups, forwarded headers), the `PROXY_NETWORK` variable, and the database-backup warning (that backups to the local disk CBFS provider sit on the same host as the database and are only partial protection; the Backblaze or S3 provider in production places them offsite).
- **`cbdebugger`** present in the dev stack only.

### Exit condition

`docker compose -f compose.yaml -f compose.dev.yaml up` brings up the full local environment. Both surfaces load their AdminLTE shells. A test client user and a test agent user can each log in and reach their respective surface; the other surface is correctly denied. `/agent/admin` returns 403 for a non-admin agent. CI is green. Nothing does anything useful yet, but the skeleton is complete, correct, and deployable.

---

## Phase 1 — Ticketing spine

Goal: the core of the product works end to end. Tenancy is real from the first migration. The central audit log exists. Tickets can be created, worked, and resolved through the UI, including tickets from unregistered senders.

Build order within the phase: `contacts` and `audit` first (both are low-level modules others depend on), then `tickets`, then a basic `agent` workspace. `contacts` is first because it owns the tenant-boundary entities and the isolation primitive everything else depends on; `audit` is built alongside it because modules begin writing to the audit log as soon as they perform significant operations.

### Deliverables

**`contacts` module:**

- `Organization`, `Office`, and `Contact` entities, with their first migrations. `Organization` is the tenant boundary.
- The **tenant isolation primitive**: the Quick global scope (or shared base entity) that automatically filters tenant-scoped queries to the requesting user's organization. It lives here, in `contacts`. Every tenant-scoped entity in every other module will apply it.
- `Office` is optional: an organization may have none, a contact may be assigned to none.
- The **client-side role system** on the `Contact` account, built as a small extensible role system rather than a hardcoded boolean. **Organization Admin** is the first role: organization-wide, granting view-and-act access (reply, close, reassign within the org; reassignment moves ticket ownership among contacts in the same organization and never touches the assigned provider agent).
- **Client account provisioning**: agent-created accounts are the path built in this phase. Provider agents create client `Contact` accounts. The groundwork is laid for Organization Admins to invite contacts within their own organization, which is the target model, but the agent-created path is what must work in Phase 1.
- Company grouping with domain mapping, contact merge, customer tiers.
- The `contacts` service layer, through which every other module reaches contact and organization data.
- Specs: tenant scope enforcement (a client user cannot see another organization's data), the Organization Admin role, office assignment, agent-created provisioning.

**`audit` module:**

- The `AuditEvent` entity, with its first migration.
- The `audit` service layer: the interface other modules call to record significant operations. It is built to be extended with new event types over time.
- The admin-facing reporting and search UI for audit events, surfaced within `/agent/admin`.
- As `contacts` and `tickets` perform significant operations in this phase (role assignments, contact merges, ticket lifecycle events worth auditing), they write to the `audit` log through its service layer. This is distinct from `tickets` owning `TicketEvent` for the agent-facing ticket timeline; the two logs coexist deliberately.
- Specs: event recording, the search and reporting UI, and that the audit log captures cross-module operations.

**`tickets` module:**

- `Ticket`, `TicketMessage`, `TicketEvent`, `TicketLink`, `Attachment`, `Tag`, and the custom-field entities, all with migrations. Every tenant-scoped table among these carries `organization_id` and applies the `contacts` tenant scope from its first migration.
- Ticket lifecycle and status workflow (new, open, pending, on-hold, resolved, closed), priority levels, ticket types (incident, request, problem, question).
- Threaded conversations with public replies and internal notes. Internal `TicketMessage` records are never visible to any client-side role.
- **Accountless tickets from unregistered senders.** A `Ticket` can exist with no `Contact`, identified only by a raw originating email address. Such a ticket has no `organization_id`, sits outside the tenant scope, and is visible only to provider agents. The data model carries the originating email address as a first-class field on the ticket so an accountless ticket is fully formed. This is built in Phase 1, not deferred.
- **Promote sender to contact.** A provider agent can create a `Contact` account from the originating email address of an accountless ticket (the agent-created provisioning path from `contacts`). Doing so assigns the ticket into an organization and brings it under the tenant scope. This action is surfaced in the agent ticket view.
- Ticket merging and splitting, parent/child and linked-ticket relationships, assignment and reassignment with ownership history, watchers and followers.
- Full ticket timeline through `TicketEvent`: every state change recorded. Significant events are also written to the central `audit` log.
- Attachments and inline images through CBFS (local disk provider in development), constrained by the configured upload size and file-type limits.
- Ticket tags and custom fields per ticket type.
- The `tickets` service layer, which `channels`, `portal`, and `widget` will later use to create tickets.
- Specs: lifecycle transitions, the timeline, internal-note visibility, attachment round-trip through CBFS, custom fields, accountless tickets, and the promote-sender-to-contact flow including that it correctly brings the ticket under tenant scope.

**Basic `agent` workspace:**

- `Agent` and `Team` entities with migrations.
- A working technician view of tickets: list, open, reply, change status, assign and reassign, add internal notes.
- The unknown-sender workflow in the UI: an accountless ticket is clearly represented, with a "create account from sender" action and a "block this sender" action (the latter adds the sender's address or domain to the `channels` blacklist; the blacklist entities themselves are owned by `channels` and built in Phase 2, so in Phase 1 this is wired to the `channels` service interface that Phase 2 completes, or the button is staged and activated in Phase 2 if the blacklist store is not yet present).
- Enough of the `/agent` shell to work a ticket from creation to resolution.
- Collision detection and the unified customer timeline are accounted for in the data model now even though their full UI lands later.
- Specs: agents can work tickets across organizations; the cross-organization visibility is correct; accountless tickets are visible to agents and never to client users.

### Exit condition

A provider agent can log into `/agent`, see tickets across all organizations, open one, reply, add an internal note, reassign it, and resolve it, with every step recorded in the ticket timeline and significant events in the central audit log. A ticket from an unregistered sender exists as an accountless ticket, visible only to agents, and an agent can promote that sender into a `Contact`, which pulls the ticket into an organization. A client user logging into `/` can see their own organization's tickets and no others, and never sees accountless tickets. An Organization Admin can see and act on all tickets in their organization. The `audit` module's search UI shows cross-module events. Tenant isolation holds under test. Attachments work through CBFS on local disk within the configured limits. CI is green.

---

## Phase 2 — Intake

Goal: tickets can arrive through every customer-facing channel, the inbound blacklist works, the knowledge base exists, and conventional search is in place.

### Deliverables

**`channels` module:**

- Channel intake and normalization. Inbound email parsing first: an inbound email becomes a `Ticket` (or a `TicketMessage` on an existing ticket) through the `tickets` service layer. When the sender is not a known `Contact`, the result is an accountless ticket (the model built in Phase 1).
- **Inbound mechanism: IMAP polling.** Inbound mail arrives by polling a mailbox over IMAP. The channel intake is written behind an abstraction so an alternative mechanism (a mail-provider inbound webhook, for example) can be added later without disturbing the rest of the module.
- **The inbound blacklist.** `channels` owns the email-address and domain blacklist entities. Every inbound email is checked against the blacklist before a ticket is created; matches are dropped or quarantined rather than becoming tickets. The blacklist has two entry points: the automatic check on intake, and the manual "block this sender" action surfaced on tickets in the agent workspace (staged in Phase 1, fully activated here once the blacklist store exists). A guard against auto-responder loops: an inbound message that looks like an automated bounce or auto-reply does not generate an auto-acknowledgement back.
- Live chat intake and a contact form, both normalizing into the same ticket model.
- Outbound email with correct threading headers, through `cbmailservices`. In development, all outbound mail is trapped by Mailpit.
- Channel-config entities and the blacklist entities owned by `channels`.
- Specs, including email assertions through the Mailpit JSON API, blacklist enforcement on intake, and the loop guard.

**`portal` module (the `/` surface):**

- Authenticated client users land on their ticket overview: open and past tickets, submit and track requests.
- Unauthenticated visitors get the portal entry point: submit a ticket, browse the public knowledge base, guest submission with email verification.
- All ticket creation goes through the `tickets` service layer.
- Basic rate limiting on the public submission endpoints (guest submission, contact form), built alongside the endpoints rather than deferred to Phase 6.

**`widget` module:**

- The embeddable support widget intake and its public endpoints, kept separate from `portal` so it can be cached and rate-limited independently.
- Ticket creation through the `tickets` service layer.
- Basic rate limiting on the widget intake endpoints.

**`knowledgebase` module:**

- `Article`, `ArticleVersion`, `ArticleFeedback`, `Category`, and the `ArticleOrganization` join, with migrations.
- Article authoring with versioning and draft/publish states, categories and folders, article feedback, view analytics.
- Three-tier visibility: **public** (anyone, including unauthenticated visitors), **organization-scoped** (members of one or more specified organizations, via the `ArticleOrganization` join, many-to-many), **internal** (provider agents only).
- Specs covering each visibility tier and that organization-scoped articles respect the tenant boundary.

**Conventional search:**

- PostgreSQL native full-text search across tickets and the knowledge base. This is the baseline search experience and works with AI disabled. It is built here, alongside the knowledge base, because that is the first content that needs searching. The optional `pgvector` semantic search added in Phase 4 sits alongside this, it does not replace it.
- Specs for full-text search relevance and that search respects tenant scope and article visibility.

### Exit condition

A ticket can be created by inbound email (via IMAP polling), by live chat, by the contact form, through the portal, and through the embeddable widget, and every one of them lands as a normalized ticket. The inbound blacklist blocks listed addresses and domains on intake, and an agent can add a sender to it from a ticket. Outbound email is correctly threaded and trapped by Mailpit in development. A client can browse the public knowledge base unauthenticated and organization-scoped articles when logged in. Full-text search works across tickets and the knowledge base with AI disabled. Public endpoints have basic rate limiting. CI is green.

---

## Phase 3 — Rules and SLA

Goal: the system automates routing and enforces service-level agreements on a schedule.

### Deliverables

**`automation` module:**

- `AutomationRule` and related config entities, with migrations.
- A rules engine for trigger-condition-action automations: on create, on update, time-based.
- Escalation rules, round-robin and load-based assignment strategies, scheduled and recurring tickets, auto-responses and acknowledgements, approval workflows for request-type tickets.
- Specs for rule evaluation and each assignment strategy.

**`sla` module:**

- `SlaPolicy`, `BusinessHoursCalendar`, and related entities, with migrations.
- SLA policies tied to priority or customer tier, business-hours calendars and holiday schedules, first-response and resolution targets, breach warnings and escalations, SLA pause and resume during pending states.
- Specs for target calculation against business-hours calendars, breach detection, pause and resume.

**Scheduler:**

- The ColdBox scheduled tasks running in the `scheduler` container come alive here: SLA breach checks, recurring-ticket creation, and the groundwork for scheduled report exports and data retention sweeps that later phases complete.
- **The nightly database backup task.** It runs `pg_dump`, compresses the dump (gzip), and writes it to the configured CBFS provider under a dated path (for example `backups/2026-05-14-….dump.gz`). It prunes dumps older than the `.env`-configured retention. In development the backup lands on local disk; in production it lands on Backblaze B2. The PostgreSQL client tools needed for `pg_dump` were included in the container image in Phase 0.
- Specs: the backup task produces a compressed dump at the expected path and prunes correctly against the retention setting.

### Exit condition

A new ticket is automatically routed by automation rules. An SLA policy applies to a ticket, its first-response and resolution targets are computed against a business-hours calendar, a breach warning fires on schedule, and pause/resume works during pending states. The nightly database backup runs, produces a compressed dated dump on the configured CBFS provider, and prunes old dumps per the retention setting. The scheduler container is doing real work. CI is green.

---

## Phase 4 — AI (optional layer)

Goal: the AI layer exists, is entirely optional, and the system remains fully functional with it disabled.

This phase is built so that everything in it can be turned off. Before writing any AI feature, build the capability flag and the absence behavior, and verify the application is fully functional with no AI configuration.

### Deliverables

**`ai` module and middleware:**

- `AiInteraction` entity with migration.
- The **AI middleware facade**: the only code that imports `bx-ai`. Every AI feature calls the facade, never the provider directly. The facade provides one place for prompt and response logging (`AiInteraction`), PII redaction before any payload leaves the system, per-feature and per-tenant rate limiting, provider abstraction, deterministic-response caching where appropriate, and the single capability flag the rest of the app keys off of.
- **The capability flag**: a single environment-driven source of truth for whether AI is enabled.
- **Absence behavior, built and verified first**: every AI-related CBWire component and view partial checks the capability flag and renders nothing when AI is off, enforced at the layout and component level. Feature modules treat AI as an optional collaborator: if the flag is off, the AI call site is skipped and the non-AI path proceeds. cbq jobs for AI work are only enqueued when AI is enabled.
- **Provider configuration through `.env`**: provider selection, credentials, and model are all environment variables. OpenRouter is the configured provider for development and production. The facade stays provider-agnostic so any `bx-ai`-supported provider can be slotted in by changing `.env`.

**AI features**, each a service behind the facade, each individually gated so it can be toggled independently once AI is on:

- Auto-triage: classify category, urgency, and sentiment on inbound tickets, feed `automation` for routing.
- Suggested replies: draft agent responses from ticket context and past resolutions.
- Knowledge base suggestions: surface relevant articles to the agent, and to the customer before submission.
- Thread summarization: condense long ticket threads for an agent picking up a ticket.
- Auto-tagging and entity extraction from ticket bodies.
- Sentiment and escalation-risk scoring.
- Customer-facing AI assistant: deflects common questions, hands off to a human with full context.
- Reply tone and quality check before an agent sends.
- Semantic search across tickets and the knowledge base, backed by `pgvector` in the main database. With AI off, search falls back to conventional database search and no embeddings are generated or stored.
- Post-resolution article drafting: generates a knowledge base draft from a well-resolved ticket. The draft defaults to **internal and unpublished**, so a human must explicitly choose any broader exposure.

- All AI calls run as cbq jobs where latency would otherwise block a request.
- Specs: provider calls mocked, asserting redaction, logging, rate limiting, and the capability-flag behavior, including that no AI UI renders when AI is disabled.

### Exit condition

With no AI configuration in `.env`, the application is fully functional and not one AI-related UI element appears anywhere. With OpenRouter configured, the AI features light up, each can be toggled independently, AI work runs as cbq jobs, and semantic search uses `pgvector`. The middleware facade is the only code touching `bx-ai`. CI is green with AI both enabled and disabled.

---

## Phase 5 — Insight and admin

Goal: reporting dashboards, the notification fan-out, and the full administration surface.

### Deliverables

**`reporting` module:**

- Dashboards on AdminLTE 4 widget and chart layouts: ticket volume, response and resolution times, SLA compliance, agent performance, channel breakdown, backlog aging.
- Scheduled report exports (the scheduler work from Phase 3 completed here) and a raw data export for teams that want their own BI tooling. Large exports run as cbq jobs rather than inline, so a heavy export does not block a request.
- `reporting` owns no entities; it reads across other modules' service layers.
- Charts via a Bootstrap 5-compatible library.

**`notifications` module:**

- Notification templates and delivery-preference entities, with migrations.
- Outbound fan-out: email, Slack or Teams, in-app.
- `notifications` is an event consumer: other modules announce events, `notifications` decides delivery. Wire the events that earlier phases' modules emit.
- Bounce handling for outbound email: a hard bounce on a notification is recorded and surfaced rather than silently lost. User-facing notification preferences and the unsubscribe handling that outbound email requires are part of this module's delivery-preference work.

**`admin` module (full surface):**

- The full administration and configuration surface, nested in `agent` at `/agent/admin`, gated by its own module-level cbSecurity rules.
- RBAC management, team and group management, business-hours config, the custom field and form builder, branding and white-labeling, email server settings, the inbound blacklist management UI, ticket field and workflow customization.
- Audit log views are surfaced here but the underlying reporting and search belong to the `audit` module (built in Phase 1); `admin` mounts that UI within `/agent/admin`.
- Agent bulk actions that operate on many tickets at once run as cbq jobs rather than inline.

### Exit condition

Provider staff with the right roles can see reporting dashboards, configure the system through `/agent/admin`, and the system fans out notifications through email and chat on the relevant events. Scheduled exports run. `/agent/admin` remains 403 for non-admin agents. CI is green.

---

## Phase 6 — Integrations and hardening

Goal: the API matures, external integrations land, the system is hardened, and the production storage path is proven.

### Deliverables

**`api` module maturity:**

- The versioned REST API across the product surface, JWT auth, serialization through mementifier, OpenAPI docs auto-generated through cbswagger.
- Outbound webhooks: an event dispatch system other systems can subscribe to.

**External integrations:**

- Connectors for Slack or Teams notifications, Jira or other issue trackers, GitHub, and billing systems.

**MFA:**

- TOTP-based multi-factor authentication (the QR-code enrollment kind: the user scans a QR code into an authenticator app, which then generates rotating six-digit codes). RFC 6238 TOTP, no SMS.
- **Optional for client users, required for provider agents.** A client user may choose to enable MFA on their own account; a provider agent account must have MFA, because agent accounts see across all client organizations and are higher-value targets.
- **Recovery codes**: when a user enables TOTP, a set of one-time recovery codes is generated for them to save, so a lost or wiped device does not mean a locked-out account.
- **Admin reset path**: a provider admin can reset MFA enrollment on an account, in the `/agent/admin` surface, for the case where a user loses both their device and their recovery codes.
- Specs: enrollment, code verification, the optional-for-clients and required-for-agents enforcement, recovery codes, and admin reset.

**Hardening:**

- Rate limiting on public endpoints.
- Data retention policies and the retention sweeps in the scheduler.
- GDPR-style data export and deletion.
- A security review pass: cbSecurity rules across both surfaces, the tenant isolation scope, internal-note visibility, the `/agent/admin` 403 behavior, PII redaction before the AI layer.

**Backblaze B2 verification gate:**

- Before the project is considered deployment-ready, the Backblaze B2 CBFS provider is tested and verified end to end: upload, retrieval, signed-URL generation (including for image-attachment thumbnails), and access control on private buckets.
- Development runs on the local disk provider throughout, so this is the explicit point at which the production storage path is proven. If signed URLs prove troublesome here, the documented fallback is streaming files through the application behind cbSecurity checks.

### Exit condition

The REST API is documented and usable with JWT auth and webhooks. The external connectors work. TOTP MFA works, is required for provider agents and optional for client users, issues recovery codes, and can be reset by an admin. Rate limiting, retention, and GDPR export/deletion are in place. The security review has passed. The Backblaze B2 provider is verified end to end. The system is deployment-ready.

---

## Data model reference

This is the entity model as understood at planning time, organized by owning module. It is a working reference, not final DDL; exact columns, indexes, and constraints are settled during each phase's migrations. Every tenant-scoped entity carries `organization_id` and applies the `contacts` tenant scope from its first migration.

### `contacts`

- **Organization** — the tenant boundary. Has many Contacts, has many Offices, has many domain mappings, has SLA policy assignments, has a tier.
- **Office** — belongs to Organization, has many Contacts. Optional grouping within an organization. Not part of the isolation boundary.
- **Contact** — belongs to Organization, optionally belongs to an Office, has many Tickets, has client-side roles (Organization Admin being the first). The `organization_id` here is the anchor for the tenant global scope. Tenant-scoped.
- **(domain mapping entity)** — maps email domains to an Organization.

### `tickets`

- **Ticket** — belongs to a Contact *or* originates from a raw email address with no Contact (an accountless ticket). When it has a Contact it belongs to an Organization and is tenant-scoped; when accountless it has no `organization_id` and is provider-only-visible until an agent promotes the sender into a Contact. Belongs to Agent (assignee). Has many TicketMessages, has many TicketEvents, has many Attachments, belongs to many Tags, has many Watchers. Linked to other Tickets through TicketLink. Has a status, a priority, a type. Carries the originating email address as a first-class field so an accountless ticket is fully formed.
- **TicketMessage** — belongs to Ticket, has a visibility flag (public or internal), belongs to an author (Contact or Agent). Internal messages are never visible to any client-side role. Tenant-scoped where its ticket is.
- **TicketEvent** — belongs to Ticket, records a state transition for the agent-facing ticket timeline. This is the ticket's own history, distinct from the cross-cutting `audit` log.
- **TicketLink** — join between two Tickets (parent/child or linked).
- **Attachment** — belongs to Ticket or TicketMessage. Stores a CBFS reference (provider plus path), not the file bytes, plus metadata (filename, size, content type, uploader). Constrained on creation by the configured upload size and file-type limits.
- **Tag** — belongs to many Tickets.
- **CustomField** and **CustomFieldValue** — polymorphic, attachable to Ticket, Contact, or Organization.

### `audit`

- **AuditEvent** — a cross-cutting audit log entry: who performed a significant operation, what they did, when, and against what. Written by many modules through the `audit` service layer. Built to be extended with new event types. Distinct from `tickets`'s `TicketEvent`, which is the agent-facing ticket timeline.

### `agent`

- **Agent** — belongs to many Teams, has many assigned Tickets, has RBAC roles. Provider-side; not organization-scoped.
- **Team** — has many Agents, has queue and assignment config.
- **(agent-local entities)** — saved filters and similar agent workspace state.

### `knowledgebase`

- **Article** — belongs to Category, has many ArticleVersions, has many ArticleFeedback records. Has a visibility type: public, organization-scoped, or internal.
- **ArticleVersion** — belongs to Article; the versioning history.
- **ArticleFeedback** — belongs to Article; "was this helpful" and similar.
- **Category** — has many Articles.
- **ArticleOrganization** — join between Article and Organization, used only for organization-scoped articles. Many-to-many: an article can target several organizations.

### `channels`

- **(channel-config entities)** — configuration for the inbound and outbound channels, including the IMAP polling settings.
- **(blacklist entities)** — the email-address and domain blacklist, checked on every inbound message before a ticket is created.

### `sla`

- **SlaPolicy** — has first-response and resolution targets, belongs to a BusinessHoursCalendar, applies to a priority or a tier.
- **BusinessHoursCalendar** — business hours and holiday schedules, with its own time zone; SLA target calculation runs against it.

### `automation`

- **AutomationRule** — has a trigger, conditions, and actions as structured config.
- **(related config entities)** — escalation and assignment-strategy configuration.

### `ai`

- **AiInteraction** — logs every AI call: feature, prompt hash, provider, tokens, latency, outcome. Written only when AI is enabled.

### `notifications`

- **(notification template entities)** — templates for the outbound channels.
- **(delivery-preference entities)** — per-recipient or per-event delivery preferences, including unsubscribe state.

### `admin`

- **(RBAC entities)** — roles, permissions, and their assignments on the provider side.
- **(configuration and branding entities)** — branding, email server settings, custom field and form definitions.

### Owns no entities

`core`, `portal`, `widget`, `reporting`, `api`. These modules either provide shell and routing or read across other modules' service layers.

---

## Known gaps and deferred decisions

These are recognized gaps in the plan. Each is here so it is consciously tracked rather than silently missing or improvised. Each is marked as scoped into a phase, deferred, or operator responsibility. Do not expand these into features without checking with the human first.

- **Malware scanning of uploads** — *deferred decision.* File uploads are constrained by size and type from Phase 0, but uploaded files are not scanned for malware. Adding scanning means adding a scanning service or an external API dependency to the stack. This is a deliberate deferral, not an oversight; revisit if the threat model warrants it.
- **Observability beyond health checks and logs** — *deferred decision, likely operator-facing.* Phase 0 provides health-check endpoints and structured LogBox logging. There is no error tracking, alerting, or metrics, and the `worker` and `scheduler` containers fail quietly by nature (a stuck queue or a scheduled task that stopped running is invisible without something watching). Whether this is met with operator-side tooling or a light in-app integration is an open decision. It is intentionally not part of the `audit` module, which is a business and compliance concern, not a system-health one.
- **Outbound email deliverability infrastructure** — *operator responsibility, with one application piece.* SPF, DKIM, and DMARC are DNS and mail-infrastructure concerns owned by the operator and documented in the README. Bounce handling for outbound notifications is application work and is scoped into Phase 5 with `notifications`.
- **Authentication lifecycle details** — *scoped into Phase 0, no large decision.* Password reset, account lockout after failed attempts, session timeout, and concurrent-session policy mostly come from cbSecurity and cbauth. Phase 0 must configure these explicitly rather than silently accepting framework defaults. Email verification for new client accounts is part of the provisioning work in `contacts`.
- **Data retention and deletion mechanics** — *scoped into Phase 6, flagged as non-trivial.* Phase 6 lists retention policies, retention sweeps, and GDPR-style export and deletion. Deletion in this system is genuinely hard: a `Contact` has tickets, messages, attachments, and audit events, and a whole `Organization` may someday need offboarding (export everything, then purge). The choice between cascading deletes, soft deletes, and anonymize-in-place is a real design decision that Phase 6 must make deliberately. It is called out here so Phase 6 does not underestimate it.
- **Single sign-on (SSO)** — *deferred, explicit future addition.* SSO (OIDC or SAML) is deliberately not in scope. All authentication, client-side and provider-side, is local credentials through cbSecurity and cbauth, plus the TOTP MFA described in Phase 6. SSO may be added later as its own piece of work; it is recorded here so it is not improvised back into the build. Account provisioning does not depend on it (see Phase 1, agent-created provisioning).
- **Disaster recovery** — *operator responsibility.* The nightly database backup task (Phase 3) writes compressed, dated dumps to the configured CBFS provider, and the README warns about the local-disk-provider case. That is a real and valuable layer, but it is not a full disaster-recovery plan. Point-in-time recovery, tested restores, and replication are operator territory and noted as such in the README.

---

## If you need more detail than this plan carries

This plan covers a seventeen-module system in one document. That is deliberate: it keeps the whole build legible from a single file. But a phase may turn out to need more detail than the plan carries, for example the exact shape of the automation rules engine in Phase 3, or the structure of the custom field and form builder in Phase 5.

When that happens, do not inflate this file. Instead, create a per-module specification file under `docs/modules/`, named for the module (for example `docs/modules/automation.md`), and write the additional detail there. Write these just in time, at the start of the phase that needs them, not all upfront. A module spec should cover only what this plan leaves underspecified: entity columns and constraints, service-layer interfaces, event contracts, edge cases, and UI structure. It must not contradict `CLAUDE.md` or this build plan; if writing one surfaces a genuine conflict or an unanswered question, stop and raise it with the human rather than resolving it unilaterally.

If you create module spec files, add a line to the relevant phase above pointing to them, so the plan and the specs stay cross-referenced.

---

## Phase summary

| Phase | Theme | Exit condition in one line |
|---|---|---|
| 0 | Scaffolding | Empty repo becomes a runnable, tested, deployable skeleton with all seventeen modules wired. |
| 1 | Ticketing spine | Tickets created, worked, resolved end to end, including accountless tickets from unknown senders; tenancy and the central audit log real from the first migration. |
| 2 | Intake | Tickets arrive through every channel, the inbound blacklist works, the knowledge base exists with three-tier visibility, full-text search is in place. |
| 3 | Rules and SLA | Automated routing and scheduled SLA enforcement work; the nightly database backup runs. |
| 4 | AI (optional layer) | AI features work when configured; system fully functional and AI-UI-free when not. |
| 5 | Insight and admin | Reporting dashboards, notification fan-out, full admin surface. |
| 6 | Integrations and hardening | API matured, integrations landed, hardened, Backblaze verified, deployment-ready. |
