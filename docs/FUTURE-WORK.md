# TesseraBX Future Work

Items the original build plan called for or implied that are not in the shipped product. Each is tracked here so it is consciously deferred rather than silently missing.

Do not improvise any of these into the product without checking with the human. The plan governs; this file records the gap.

---

## MFA for client (Contact) accounts

**Build plan reference:** Phase 6 — "Optional for client users, required for provider agents."

**Status:** Required-for-agents shipped (`modules_app/agent/models/TotpService.bx`, `modules_app/agent/handlers/Mfa.bx`, admin reset via `agent/modules/admin/handlers/Users.bx` `resetMfa()`). Optional-for-clients was never built.

**Why it is deferred:** The agent path is mandatory because agents see across organizations. The client path is opt-in by definition and does not protect a higher-privilege surface — a Contact's account already only exposes their own organization's data, which the tenant scope guarantees independently of MFA. Shipping client MFA also has a UX cost (enrollment flow on the `/` surface, password-only fallback for accounts that decline, recovery-code rendering inside the portal layout) that did not fit the Phase 6 cut.

**What it would take to build:** Mirror the agent path against the `contacts` table. Add `mfa_*` columns to a new `contacts` migration. Add a `portal:Mfa` handler with the same setup / verify / recovery-codes actions. Add a per-contact "Enable two-factor authentication" toggle on the contact's profile page. The portal `Session.create` handler branches on `contact.getMfaEnabled()` exactly the way the agent path does. Reuse `TotpService@agent` from the agent module — the RFC 6238 implementation is account-family-agnostic; only the storage table differs.

**Estimated effort:** 4-6 hours including tests. Self-contained slice; no cross-module dependencies.

---

## External integrations: Jira, GitHub, billing connectors

**Build plan reference:** Phase 6 — "Connectors for Slack or Teams notifications, Jira or other issue trackers, GitHub, and billing systems."

**Status:** Slack / Teams shipped via the notifications fan-out (`SLACK_WEBHOOK_URL`, slack-compatible payload accepted by Teams). Jira / GitHub / billing connectors are not built.

**Why it is deferred:** Each connector is a meaningful slice on its own (OAuth flow with the third party, a bidirectional sync table per integration, conflict reconciliation, drift detection). The build plan's intent — give other systems a way to subscribe to TesseraBX events — is met through the generic [outbound webhooks](../modules_app/api/models/WebhooksService.bx) shipped in 6b. A subscriber on the customer's side can adapt the signed JSON payload into Jira / GitHub / their billing system without any TesseraBX-side connector code.

**What it would take to build:** Per-connector. The webhook payload is the wire contract; consumers map it to the third party. If a first-party connector becomes important, build it as its own module under `modules_app/integrations/<name>` so the dependency graph stays clean — none of the existing modules should grow connector code.

---

## Watchers / followers, ticket merging, ticket splitting, collision detection

**Build plan reference:** Phase 1 — "watchers and followers, ticket merging and splitting, parent/child and linked-ticket relationships ... Collision detection and the unified customer timeline are accounted for in the data model now even though their full UI lands later."

**Status:** Parent/child + linked-ticket relationships shipped via `TicketLink`. Watchers, followers, ticket merging, ticket splitting, and collision detection are not surfaced in the UI; the data model carries the columns / tables they would attach to.

**Why it is deferred:** Each of these is a small UI slice on top of the existing data model. They are not load-bearing for the rest of the system — the SLA timer, the audit log, the assignment flow, and the notification fan-out all work without them.

**What it would take to build:** Mostly UI work on top of the existing ticket model. Merging is the largest piece (decide the receiving ticket, copy messages / events / attachments across, redirect the URL of the merged-away ticket, write an audit event). Splitting is the inverse plus a copy of the original's tags. Collision detection is a CBWire ping-and-broadcast loop on the ticket show page. Watchers / followers reuse the `notifications` module's preference rows with a new event key.

---

## Live chat intake

**Build plan reference:** Phase 2 — "Live chat intake and a contact form, both normalizing into the same ticket model."

**Status:** Contact form shipped (`portal:Contact`). Live chat is not built.

**Why it is deferred:** Live chat requires a long-lived bidirectional connection (WebSocket via cbwire or a server-sent-events fallback) and a chat-routing service distinct from the ticket lifecycle. The contact form fills the synchronous-intake gap on the public surface; the widget covers the same flow on third-party sites.

**What it would take to build:** A `channels:Chat` handler that opens a session, a CBWire component that drives the conversation, and a service that materializes an idle chat into a `Ticket` once a configurable idle threshold elapses. The hand-off from chat to ticket — preserving conversation context — is the architectural work; the rest is plumbing.

---

## Guest submission with email verification

**Build plan reference:** Phase 2 — "submit a ticket, browse the public knowledge base, guest submission with email verification."

**Status:** Guest submission is supported via the contact form and creates an accountless ticket. The follow-up email-verification round trip is not built.

**Why it is deferred:** Accountless tickets already work; the verification step is hardening against typo'd email addresses and would block honest submissions while not stopping a determined adversary (anyone who can read inbound email can verify themselves). The build plan called for it; the operational value did not justify the friction at Phase 2.

**What it would take to build:** A `pending_ticket` table keyed by a short-lived verification token, a "click to confirm" email sent on submission, and a route that materializes the pending row into a real ticket once the token is consumed. The contact form's existing rate limit covers abuse.

---

## Auto-tagging and dedicated escalation-risk scoring as standalone AI features

**Build plan reference:** Phase 4 — "Auto-tagging and entity extraction from ticket bodies. Sentiment and escalation-risk scoring."

**Status:** Sentiment + tag suggestions are rolled into the triage service (`modules_app/ai/models/TriageService.bx` returns `priority / ticketType / tags / sentiment / rationale` in one call). There is no separate escalation-risk score.

**Why it is folded:** Each independent AI call is a round trip to the model — combining them into one prompt cuts latency and cost roughly proportional to the number of separate calls saved. The current triage prompt asks for all four classifications at once.

**What it would take to split:** Three separate services behind the `AiCapability` flag (one per concern), each with its own seeded system prompt in `ai_system_prompts`. Useful only if a deployment finds the combined call's quality lacking on one specific axis.

---

## Approval workflows for request-type tickets

**Build plan reference:** Phase 3 — "approval workflows for request-type tickets."

**Status:** Not built. Recurring tickets, escalation, round-robin and load-based assignment all shipped; approvals are the gap.

**Why it is deferred:** Approval flows need a per-tenant configuration surface (who approves what, how many approvals are required, what happens on rejection) that did not fit the Phase 3 cut. The build plan's other automation primitives cover the cases shipped customers were asking for.

**What it would take to build:** An `approval_rules` table (entity_type, conditions, required_approvers, on_rejection_action), an `approvals` join table on tickets, a CBWire approve / reject panel in the agent ticket view for designated approvers, and an automation action `request_approval` that creates the approval rows and pauses the ticket until they all resolve.

---

## Continuous storage verification

**Build plan reference:** Implied by Phase 6f — the `/agent/admin/storage` verification gate.

**Status:** Operator-triggered button at `/agent/admin/storage`. Not run on a schedule.

**Why it is deferred:** Verifying a private bucket on every scheduled tick consumes bandwidth and incurs B2 / S3 list+get+delete API costs for no real signal in normal operation. The threat model is "the credentials silently rotated" or "the bucket policy drifted" — both human-triggered events that justify a human-triggered verification.

**What it would take to build:** A `core:storage-verify` scheduled task that calls `StorageVerifyService.verify()` and writes the report to a `storage_verify_runs` table. The admin storage page surfaces the most recent run alongside the on-demand button.

---

## Observability beyond health checks and logs

**Build plan reference:** "Known gaps and deferred decisions" in `BUILD-PLAN.md`.

**Status:** Health-check endpoints (`/health`, `/health/worker`) and structured LogBox logging shipped in Phase 0. Error tracking, metrics, alerting are not built.

**Why it is deferred:** Operator-side tooling (Sentry, Datadog, Prometheus, etc.) typically owns this responsibility, and the integration is operator-specific. The application is set up to be observed; the observer is the operator's choice.

**What it would take to build (in-app option):** A LogBox appender wired to whichever sink the operator picked, plus a `BackgroundJobsAlive` heartbeat task that pings a watchdog URL every minute so a stuck `worker` or `scheduler` is detected externally.

---

## Single sign-on (OIDC / SAML)

**Build plan reference:** "Known gaps" — explicitly deferred.

**Status:** Local credentials only, via cbauth + cbSecurity, plus TOTP MFA on the agent surface.

**Why it is deferred:** SSO is its own slice of work and was deliberately not in scope. The current authentication model is correct for the deployment shape the plan targets; SSO can be layered on later through cbsecurity's pluggable validator interface without disturbing the credential path.

**What it would take to build:** Add an OIDC client module (cbsso or equivalent), register an OIDC validator in `cbsecurity.firewall.validator`, and add an SSO entry button to the agent + portal login pages that hands off to the IdP. The existing local-credential path stays for accounts that don't go through the IdP.
