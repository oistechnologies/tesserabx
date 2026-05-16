# TesseraBX Security Review

This document records the Phase 6 security-review pass. It walks the five concrete checks the build plan called out (`docs/BUILD-PLAN.md` line 286), names the code that enforces each one, and lists open follow-ups.

The review is a snapshot. Re-run it after any change to the cbSecurity rules, the tenant scope, the agent / admin firewall surfaces, the AI middleware, or the JWT issuance path.

---

## 1. cbSecurity rules across both surfaces

**Status:** ✅ pass

**Location:** [`config/Coldbox.bx`](../config/Coldbox.bx) — `moduleSettings.cbsecurity.firewall.rules`.

The firewall declares three rules in order of specificity:

1. `^agent/admin($|/)` — requires the `agent-admin` role. Anyone else hits `agent:Session.unauthorized` via the `override` action (not `block`) because cbsecurity's `block` hardcodes 401; the CLAUDE.md contract requires 403 here. Verified by [`AgentSessionSpec.bx`](../modules_app/agent/tests/specs/AgentSessionSpec.bx) and by manually curling `/agent/admin/*` without an admin role.
2. `^agent(/|$)` — requires the `agent` role. Login / logout / unauthorized are whitelisted. Unauthenticated requests redirect to `/agent/login`.
3. `^(account|tickets|profile)(/|$)` — the portal's authenticated paths. Unauthenticated requests redirect to `/login`.

The `/api` surface intentionally does not appear in the firewall. cbsecurity 3.7 only honors the global `firewall.validator` (no per-rule override), and the global validator is session-based via cbauth — which is wrong for a stateless JSON API. Each API handler action calls `ensureAgent(event, prc)` instead, which parses the JWT through `JwtService@cbsecurity`, populates `prc.oCurrentUser`, and renders 401/403 in JSON on failure. See [`api/handlers/Tickets.bx`](../modules_app/api/handlers/Tickets.bx) `ensureAgent()`.

The `/widget` and `/contact` paths are intentionally unauthenticated; the rate limiter (item 4 of this review's adjacent hardening list, and Phase 6d) is what protects them from abuse.

---

## 2. Tenant isolation scope

**Status:** ✅ pass

**Location:** [`modules_app/contacts/models/scopes/TenantScope.bx`](../modules_app/contacts/models/scopes/TenantScope.bx), wired into Quick entities through [`TesseraBXEntity`](../modules_app/contacts/models/TesseraBXEntity.bx) (the shared base entity).

Every tenant-scoped entity (Contact, Ticket, TicketMessage, TicketEvent, Attachment, Tag, kb_article_organizations join rows, notification_preferences, etc.) extends `TesseraBXEntity` and inherits the global scope. The scope reads the requesting user's organization from [`TenantContextProbe@contacts`](../modules_app/contacts/models/TenantContextProbe.bx) and adds `WHERE organization_id = ?` to every Quick query — agents bypass the scope intentionally (they see across organizations subject to RBAC), but every client-surface query goes through it.

Specs that enforce isolation:

- `TicketsServiceSpec` — `creates a contact-backed ticket and inherits the contact's organization`
- `KbVisibilitySpec` — organization-scoped articles only surface for members of the joined orgs
- `BulkActionsServiceSpec` — bulk actions across tickets respect the same isolation Quick reads enforce

**Accountless tickets explicitly opt out of tenant scope:** a ticket with no `requester_contact_id` carries `organization_id = NULL` and is visible only to provider agents. The promote-sender-to-contact flow brings it under scope by setting both columns. Confirmed by `TicketsServiceSpec` — `creates an accountless ticket without an organization`.

---

## 3. Internal-note visibility

**Status:** ✅ pass

**Location:** [`modules_app/tickets/models/TicketsService.bx`](../modules_app/tickets/models/TicketsService.bx) — `listMessagesForTicket( ticketId, includeInternal )`.

The boolean `includeInternal` flag is `true` from agent handlers and `false` from portal handlers. The implementation `whereIn`s out internal rows when the flag is false, so a client-side request that somehow got an agent's tickets struct would still not surface the internal bodies.

Specs:

- `TicketsServiceSpec` — `internal notes are excluded from the client-visible message list`

Portal handler call sites: [`portal/handlers/Tickets.bx`](../modules_app/portal/handlers/Tickets.bx) `show()` passes `false`. Agent call site: [`agent/handlers/Tickets.bx`](../modules_app/agent/handlers/Tickets.bx) `loadShowContext()` passes `true`.

The webhook fan-out's payload builder ([`api/interceptors/WebhookDispatchInterceptor.bx`](../modules_app/api/interceptors/WebhookDispatchInterceptor.bx) `buildPayload()`) does include `is_internal` on the message struct so subscribers can filter as appropriate — webhook subscribers are provider-owned integrations, not client-visible surfaces.

---

## 4. `/agent/admin` returns 403 (not 401, not 404)

**Status:** ✅ pass

**Location:** [`config/Coldbox.bx`](../config/Coldbox.bx) — the first firewall rule uses `action: "override"` with `overrideEvent: "agent:Session.unauthorized"`, which sets HTTP 403 and renders the [`session/unauthorized`](../modules_app/agent/views/session/unauthorized.bxm) view. CLAUDE.md mandates 403 here so the route's existence is acknowledged without granting access.

Confirmed by [`AgentSessionSpec.bx`](../modules_app/agent/tests/specs/AgentSessionSpec.bx) — `unauthorized handler returns 403`.

A non-admin agent gets 403 with the styled error page. An unauthenticated request redirects to `/agent/login` first (per rule 2), so they never reach the 403 path until they hold an `agent` role but not `agent-admin`. The 404 path is reserved for truly unknown routes.

---

## 5. PII redaction before the AI layer

**Status:** ✅ pass

**Location:** [`modules_app/ai/models/AiMiddleware.bx`](../modules_app/ai/models/AiMiddleware.bx) — `redactPii()` runs on every prompt before the provider call, gated by `AI_PII_REDACTION` (default `true`).

Current redaction surface:

- Email addresses → `<email>`
- (Future passes: phone numbers, credit-card-shaped digit runs. Called out in the `.env.example` comment so operators know what's covered today.)

Specs:

- `AiMiddlewareSpec` — `redactPii masks email addresses when AI_PII_REDACTION is true`
- `AiMiddlewareSpec` — `redactPii is a no-op when AI_PII_REDACTION is false`
- `TriageServiceSpec` — confirms the middleware is the only AI call path (the service never imports bx-ai directly)

Every AI feature in the application — triage, suggested replies, summarization, KB drafting, semantic search embeddings, tone check, customer assistant — calls `AiMiddleware.complete()` or `AiMiddleware.embed()`. There is no AI call site that bypasses the middleware; `grep -rn "aiChat\|aiEmbed" modules_app | grep -v /ai/` returns nothing.

---

## Adjacent hardening items (Phase 6 deliverables)

These were built in Phase 6 but were not in the original five-item review checklist. Listed here so the review document captures the full security posture as of the deployment-readiness gate.

| Item | Status | Reference |
|---|---|---|
| TOTP MFA, required for provider agents | ✅ | `modules_app/agent/models/TotpService.bx`, `modules_app/agent/handlers/Mfa.bx` |
| Recovery codes, bcrypt-hashed, single-use | ✅ | `TotpService.consumeRecoveryCode` |
| Admin MFA reset | ✅ | `agent/modules/admin/handlers/Users.bx` `resetMfa()` |
| Rate limiting on `/api/v1/auth/login` | ✅ | `api/handlers/Auth.bx` — 10 / 15min / IP, 429 + Retry-After |
| Rate limiting on `/agent/login/verify` | ✅ | `agent/handlers/Mfa.bx` — 8 / 5min / agent id, resets on success |
| Rate limiting on `/contact` and `/widget` intake | ✅ | `portal/handlers/Contact.bx`, `widget/handlers/Intake.bx` |
| Retention sweeps (notifications, audit events, webhook deliveries, AI interactions, completed cbq jobs) | ✅ | `core/models/RetentionService.bx`, scheduled at 02:30 UTC daily |
| GDPR-style data export (per contact JSON) | ✅ | `contacts/models/GdprService.bx` — `exportForContact()` |
| GDPR-style erasure (pseudonymize in place) | ✅ | `contacts/models/GdprService.bx` — `eraseContact()` |
| HMAC-signed unsubscribe tokens | ✅ | `notifications/models/NotificationsService.bx` — `HmacSHA256` with `NOTIFICATIONS_UNSUBSCRIBE_SECRET` |
| HMAC-signed webhook payloads | ✅ | `api/models/WebhooksService.bx` — `X-TesseraBX-Signature` HMAC-SHA256 |
| JWT secret with cachebox-backed token storage | ✅ | `cbsecurity.jwt.tokenStorage` |
| Private CBFS buckets, signed URLs, verification gate | ✅ | `/agent/admin/storage` verification — 5 steps green against live B2 |
| cbantisamy global form sanitizer | ✅ | Installed via `box.json`; structured form data uses base64 carrier when needed |

---

## Known gaps and open follow-ups

These are tracked rather than silently missing. Each should be considered before going to production.

- **MFA for client (Contact) accounts is not built.** The build plan called for "optional for clients, required for agents." Required-for-agents shipped; optional-for-clients is captured in [`docs/FUTURE-WORK.md`](FUTURE-WORK.md) and is a deferred-by-design decision.
- **PII redaction covers only email addresses.** Phone numbers and credit-card-shaped digit runs are stated as future passes in the `.env.example` comment. If the workload regularly handles those, extend `AiMiddleware.redactPii()` before going live with AI enabled.
- **No malware scanning on uploads.** Documented in `BUILD-PLAN.md` "Known gaps." Uploads are size + extension constrained; a scanner (ClamAV, hosted API) is operator territory.
- **`/agent/admin/storage` verification is run on demand by an operator, not on a schedule.** If credentials rotate or the bucket policy drifts, a routine check is human-triggered. Consider a `core:storage-verify` daily scheduled task if production needs the assurance continuously.
- **External integrations (Jira, GitHub, billing connectors)** were explicitly chosen out of scope at Phase 6a. They are not a security gap, but webhooks (which we shipped) are the documented escape hatch until those connectors land.

Re-evaluate this list at every major release cut.

---

## Reviewing this document

Run the suite (`box testbox run`) and walk every cross-reference in this file. Any link that 404s or any spec that no longer asserts what the relevant section claims indicates this document is out of date — fix the link / spec, or fix the underlying behavior, before merging the change that broke the contract.
