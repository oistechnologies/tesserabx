# Email Audit Report

**Scope:** Every outbound email sent by the TesseraBX host application and by the
`tesserabx-pm` project-management add-on, the action that triggers each, where
its body template and layout live, and the end-to-end workflows that produce
email.

**Repositories audited:**

- Host application: `/Users/mrigsby/Data/BoxLang-Dev/TesseraBX/GIT/tesserabx` (paths in this document are relative to that repo root).
- Add-on: `/Users/mrigsby/Data/BoxLang-Dev/TesseraBX/GIT/tesserabx-pm` (referenced as `tesserabx-pm/...`).

**Generated:** 2026-06-06. This is a point-in-time audit of the working tree.

**Updated 2026-06-06 (post-implementation):** Recommendations R1, R2, R3, and R7
have since been implemented in the host app, and R8 in the `tesserabx-pm` add-on.
This document was revised to describe the resulting state. R4 and R5 remain open;
R6 stays deferred (blocked by the known cbq-on-Postgres limitation). A per-item
status table is in section 8.2. Newly added or changed material is tagged with
its recommendation number (for example "(R1)").

---

## 1. Overview and methodology

TesseraBX sends mail through **two distinct paths**. Understanding the split is
the key to the whole report, because the same logical event (for example "a
message was added to a ticket") can travel down one path, the other, or both.

```
                          +-------------------------------+
   Path A: DIRECT SEND    |  A service composes a body in  |
   (synchronous, in code) |  code and calls compose()+send()|
                          +---------------+---------------+
                                          |
   OutboundEmailService (auto-ack, agent  |
   reply), PendingTicketsService (guest   |
   verify), ContactInviteService (invite),|
   MyAccount wire (agent email change),   v
   admin Settings (test), ScheduledExport +--> MailComposerService@core
                                               compose() -> Mail object
   ---------------------------------------     send()    -> MailService@cbmailservices
                                          ^
   Path B: NOTIFICATION-DRIVEN            |
   (template rows, fan-out per recipient) |
                          +---------------+---------------+
   A module announces an event ->         |
   an interceptor maps it to recipients ->|
   NotificationsService.dispatchForEvent  |
   -> per (channel, recipientType) template
   -> EmailChannel.send() ----------------+  (inapp rows short-circuit; only
                                              email/slack route onward)
```

- **Path A (direct send):** A service builds the subject and body in code, calls
  [`MailComposerService@core`](modules_app/core/models/MailComposerService.bx)
  `compose()` to get a branded `Mail` object, then `send()`. The body text is
  hardcoded in the service method. These emails are not template-row driven and
  are not subject to per-recipient notification preferences.
- **Path B (notification-driven):** A module announces a ColdBox event. An
  interceptor decides who should hear about it and calls
  [`NotificationsService.dispatchForEvent()`](modules_app/notifications/models/NotificationsService.bx).
  That service looks up a row in `notification_templates` for each
  `(event_key, channel, recipient_type)` tuple, renders `{{token}}`
  placeholders, writes a `notifications` row, and for the `email` channel hands
  off to [`EmailChannel`](modules_app/notifications/models/channels/EmailChannel.bx),
  which itself calls `MailComposerService`. The `inapp` channel never sends
  mail; it only lights the bell dropdown. The add-on `tesserabx-pm` sends **all**
  of its mail through Path B.

Both paths ultimately funnel through `MailComposerService`, so branding, the
HTML chrome, the plain-text alternative, the From header, and ops headers are
identical regardless of path.

**Delivery is synchronous.** No email is enqueued on cbq. Path A sends inline.
Path B writes the notification row in status `pending` and immediately calls
`EmailChannel.send()`, which flips it to `sent` or `failed`. The
`MailComposerService.send()` docblock notes that "future queueing (cbq) lands
behind this same method," but today the call is direct. The `.boxlang.json`
`spoolEnable` is `false`, so bx-mail itself also sends without spooling.

**How to read sections 3 and 4:** each email has a stable identity (its purpose),
a path (A or B), a trigger (file and function), a recipient rule, where its body
and layout come from, and any enable flag that can suppress it.

---

## 2. Mail infrastructure and configuration

### 2.1 The single composer

[`MailComposerService@core`](modules_app/core/models/MailComposerService.bx) is
the one entry point for composing outbound mail. Every send site funnels through
its `compose()` method, which:

- Resolves branding (global, or per-organization for contact recipients) and the
  logo, primary color, product name, tagline, and footer.
- Renders the inner body. When `bodyFormat="text"` (used by every current
  caller) the plain text is converted to HTML through `TextToHtml@core` for the
  HTML part, and the original text is kept verbatim for the `text/plain` part.
- Wraps the body in one of two HTML layout views (see 2.4).
- Builds a friendly From header (`"Display Name" <bare-address>`), HTML-decoding
  and quoting the display name so cbantisamy-encoded brand names do not break
  jakarta.mail.
- Adds ops headers `X-TesseraBX-Event` (the event key) and
  `X-TesseraBX-Organization`.
- For `style="notification"` with a non-blank unsubscribe URL, adds RFC 2369 /
  RFC 8058 `List-Unsubscribe` and `List-Unsubscribe-Post` one-click headers.
- Applies the admin-managed SMTP override (`SettingsService.applyMailOverride`).

`send( mail )` is a thin synchronous wrapper over `MailService@cbmailservices`.

### 2.2 cbmailservices configuration

Configured in [`config/Coldbox.bx`](config/Coldbox.bx) under
`moduleSettings.cbmailservices`:

- `from`: `MAIL_FROM` env, default `no-reply@tesserabx.local`.
- `defaultMailer`: `default`, using class
  `cbmailservices.models.protocols.CFMailProtocol` (the generic SMTP protocol,
  which on BoxLang routes through bx-mail's `cfmail`).
- Properties: `server` (`MAIL_HOST`, default `mailpit`), `port` (`MAIL_PORT`,
  default `1025`), `username` (`MAIL_USERNAME`), `password` (`MAIL_PASSWORD`),
  `useTLS` (`MAIL_TLS`), `useSSL` (`MAIL_SSL`).

### 2.3 bx-mail server configuration

[`.boxlang.json`](.boxlang.json) carries a parallel `mailServers` array that the
bx-mail runtime reads (host, port, username, password, tls, ssl from the same
env vars), with `spoolEnable: false` so sends are synchronous and immediately
visible in Mailpit.

### 2.4 HTML layout wrappers

Two chrome views live under `modules_app/core/views/emails/`:

- [`default_layout.bxm`](modules_app/core/views/emails/default_layout.bxm): the
  full notification chrome (colored header band, logo or product name, optional
  tagline, body, optional footer, optional one-click unsubscribe link). Used for
  `style="notification"` (the default).
- [`default_layout_reply.bxm`](modules_app/core/views/emails/default_layout_reply.bxm):
  the thin person-to-person chrome (a single product-name line with a colored
  bottom border, no marketing band). Used for `style="reply"`, which an
  organization opts into via its branding row; ticket auto-acks and agent
  replies resolve their style through `MailComposerService.resolveDefaultStyle()`.

If view rendering fails during early boot, `MailComposerService` falls back to an
in-code `placeholderLayout()` scaffold that mirrors the same structure.

### 2.5 Development mail trap

The dev stack ships **Mailpit** (`compose.dev.yaml`), and cbmailservices points
at `mailpit:1025`. Every send in development is captured at
`http://localhost:8025/` and nothing leaves the host.

### 2.6 Relevant environment variables

| Variable | Purpose | Default |
|---|---|---|
| `MAIL_FROM` | Default sender address | `no-reply@tesserabx.local` |
| `MAIL_FROM_DOMAIN` | Domain used to mint RFC 5322 Message-IDs | `tesserabx.local` |
| `MAIL_HOST` / `MAIL_PORT` | SMTP host and port | `mailpit` / `1025` |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | SMTP auth (blank allowed for Mailpit) | empty |
| `MAIL_TLS` / `MAIL_SSL` | Connection security | `false` / `false` |
| `OUTBOUND_EMAIL_ENABLED` | Global kill switch for ticket auto-ack and agent reply mail | `true` |
| `APP_BASE_URL` | Base for verification, invite, and unsubscribe links | `http://localhost:8080` |
| `NOTIFICATIONS_UNSUBSCRIBE_SECRET` | HMAC-SHA256 key for signed unsubscribe tokens | (required) |
| `PENDING_TICKET_TTL_HOURS` | Guest verification link lifetime | `24` |
| `CONTACT_INVITE_TTL_HOURS` | Member set-password link lifetime | `72` |
| `SLACK_WEBHOOK_URL` | Slack/Teams channel target (not email) | (optional) |

---

## 3. Email catalog: host application

### 3.1 Master summary

| # | Email | Path | Trigger (file : function) | Recipient | Enable flag |
|---|---|---|---|---|---|
| 1 | Ticket auto-acknowledgement | A | [OutboundEmailInterceptor.onTicketCreated](modules_app/channels/interceptors/OutboundEmailInterceptor.bx) -> [OutboundEmailService.sendAutoAcknowledgement](modules_app/channels/models/OutboundEmailService.bx) | Requester contact email, or raw originating email | `OUTBOUND_EMAIL_ENABLED` + source allowlist |
| 2 | Agent reply | A | [OutboundDispatchInterceptor.onTicketMessageAdded](modules_app/channels/interceptors/OutboundDispatchInterceptor.bx) -> EmailChannelAdapter -> [OutboundEmailService.sendAgentReply](modules_app/channels/models/OutboundEmailService.bx) | Requester contact email, or raw originating email | `OUTBOUND_EMAIL_ENABLED` |
| 3 | Guest pending-ticket verification | A | [PendingTicketsService.createPending](modules_app/portal/models/PendingTicketsService.bx) -> `sendVerificationEmail` | Guest sender email | (always, on guest submit) |
| 4 | Member set-password invite | A | [ContactInviteService.invite](modules_app/contacts/models/ContactInviteService.bx) -> `sendInviteEmail` | Invited member email | (always, on invite) |
| 5 | Agent email-change verification | A | [MyAccount.requestEmailChange](modules_app/agent/wires/MyAccount.bx) -> `sendVerificationEmail` | The agent's new email | (always, on request) |
| 6 | Admin test email | A | [admin/Settings.testEmail](modules_app/agent/modules/admin/handlers/Settings.bx) | Admin's address or typed address | (manual button) |
| 7 | Scheduled export ready | A | [ScheduledExportService.sendReadyEmail](modules_app/reporting/models/ScheduledExportService.bx) | Configured recipient list | (per export config) |
| 8 | Ticket status changed (agent) | B | [TicketEventsInterceptor.onTicketStatusChanged](modules_app/notifications/interceptors/TicketEventsInterceptor.bx) -> dispatch `ticket.status_changed` | Assigned agent | Per-recipient preference |
| 9 | Ticket status changed (contact) | B | same as #8 | Requester contact | Per-recipient preference |
| 10 | Ticket assigned (agent) **(R1)** | B | [TicketEventsInterceptor.onTicketAssigned](modules_app/notifications/interceptors/TicketEventsInterceptor.bx) -> dispatch `ticket.assigned` | Newly assigned agent (self-assignment + unassignment skipped) | Per-recipient preference |
| 11 | Customer-reply alert to agent **(R2)** | B | [TicketEventsInterceptor.onTicketMessageAdded](modules_app/notifications/interceptors/TicketEventsInterceptor.bx) -> dispatch `ticket.message_added` | Assigned agent (or all active agents) on a **customer** reply | Per-recipient preference |
| 12 | Contact password reset **(R3)** | A | [Session.forgotPasswordSubmit](modules_app/portal/handlers/Session.bx) -> [ContactInviteService.requestPasswordReset](modules_app/contacts/models/ContactInviteService.bx) -> `sendResetEmail` | The contact's email (neutral no-op if unknown) | (always, on request) |
| 13 | Agent password reset **(R3)** | A | [agent/Session.forgotPasswordSubmit](modules_app/agent/handlers/Session.bx) -> [AgentService.requestPasswordReset](modules_app/agent/models/AgentService.bx) -> `sendResetEmail` | The agent's email (neutral no-op if unknown) | (always, on request) |

**Important:** `ticket.created` is still deliberately **in-app only** in Path B
(no email template), because Path A's auto-ack already owns the "new ticket"
email to the requester. `ticket.message_added` is now **split**: it emails the
**agent** on a customer reply (#11, R2) but the **contact** side stays email-free,
because Path A's agent-reply already delivers to the contact. This preserves the
single-email-owner-per-recipient invariant. See 3.4 and section 7.

### 3.2 Direct-send emails (Path A), in detail

**1. Ticket auto-acknowledgement** ("we got your request")

- **Trigger:** [`OutboundEmailInterceptor.onTicketCreated`](modules_app/channels/interceptors/OutboundEmailInterceptor.bx)
  fires on the `onTicketCreated` event and calls
  [`OutboundEmailService.sendAutoAcknowledgement(ticket)`](modules_app/channels/models/OutboundEmailService.bx).
- **Conditions:** `OUTBOUND_EMAIL_ENABLED == "true"` (the service's `isEnabled()`
  gate), a non-empty recipient address, and the ticket `source` is one of
  `email`, `portal`, `widget`, `contact-form`. Tickets an agent creates from the
  dashboard are intentionally excluded (the agent already has the requester).
- **Recipient:** the linked contact's email when present, otherwise the ticket's
  raw `originatingEmail` (the accountless case).
- **Subject:** `[#<ticketNumber>] <subject>`.
- **Body:** hardcoded `autoAckBody()`: "Thanks for getting in touch. We have
  opened ticket #N for your request ..." plus the subject line and a note to
  keep the thread intact. Event key `tickets.auto_ack`.
- **Side effects:** stamps an RFC 5322 Message-ID, persists the ack as a system
  `TicketMessage` (`isSystemMessage=true`) so threading works and Path B skips
  it. If the send fails, no phantom message row is written.

**2. Agent reply** (the agent's public reply text reaches the requester)

- **Trigger:** [`OutboundDispatchInterceptor.onTicketMessageAdded`](modules_app/channels/interceptors/OutboundDispatchInterceptor.bx)
  fires on `onTicketMessageAdded`, resolves a channel adapter for the ticket
  source (falling back to the email adapter), and calls
  `EmailChannelAdapter.sendOutbound`, which delegates to
  [`OutboundEmailService.sendAgentReply(message, ticket)`](modules_app/channels/models/OutboundEmailService.bx).
- **Conditions:** `OUTBOUND_EMAIL_ENABLED == "true"`; the message is not internal;
  the message is from an agent (`message.isFromAgent()`). Contact-authored and
  internal messages return early, so a customer reply never produces an outbound
  email here.
- **Recipient:** same resolution as #1 (contact email, else originating email).
- **Subject:** `[#<ticketNumber>] <subject>`.
- **Body:** the agent's own message body, verbatim. Event key
  `tickets.agent_reply`.
- **Threading:** generates a Message-ID and walks the thread to populate
  `In-Reply-To` and `References`; stamps the Message-ID back onto the saved
  `TicketMessage` only when the send actually shipped.

**3. Guest pending-ticket verification** (double opt-in for anonymous contact-form submissions)

- **Trigger:** [`PendingTicketsService.createPending(data)`](modules_app/portal/models/PendingTicketsService.bx)
  (called from the portal contact handler's anonymous path) calls the private
  `sendVerificationEmail`.
- **Recipient:** the guest's submitted email.
- **Subject:** `Confirm your support request`.
- **Body:** hardcoded; greets, restates the subject, and gives a
  `APP_BASE_URL/contact/confirm?token=...` link valid for `PENDING_TICKET_TTL_HOURS`
  hours (default 24). Event key `portal.pending_ticket.verify`, preheader
  "Confirm your support request to create the ticket." Only a SHA-256 hash of the
  token is stored. Clicking the link materializes an accountless ticket, which
  then triggers email #1.

**4. Member set-password invite** (Organization Admin invites a client user)

- **Trigger:** [`ContactInviteService.invite(data)`](modules_app/contacts/models/ContactInviteService.bx)
  provisions a pending (inactive) contact and calls `sendInviteEmail`.
- **Recipient:** the invited member's email.
- **Subject:** `Set up your support portal account`.
- **Body:** hardcoded; a `APP_BASE_URL/set-password?token=...` link valid for
  `CONTACT_INVITE_TTL_HOURS` hours (default 72). Event key
  `portal.member_invite.set_password`. Consuming the link sets the password and
  activates the account.

**5. Agent email-change verification**

- **Trigger:** the [`MyAccount`](modules_app/agent/wires/MyAccount.bx) CBWire
  component's `requestEmailChange()` action calls `sendVerificationEmail`.
- **Recipient:** the agent's proposed new email.
- **Subject:** `Confirm your new TesseraBX agent email`.
- **Body:** hardcoded; a `APP_BASE_URL/agent/account/confirm-email?token=...`
  link valid for 60 minutes. Event key `account.email_change.verify`,
  `recipientType="agent"`.

**6. Admin test email**

- **Trigger:** the "send test" button on `/agent/admin/settings`, handled by
  [`admin/Settings.testEmail`](modules_app/agent/modules/admin/handlers/Settings.bx).
- **Recipient:** the typed address, else the current admin's email.
- **Subject:** `<productName> test email`.
- **Body:** hardcoded confirmation text. Event key `system.test`. Purely a
  configuration-verification tool.

**7. Scheduled report export ready**

- **Trigger:** [`ScheduledExportService.sendReadyEmail`](modules_app/reporting/models/ScheduledExportService.bx),
  invoked from the export run path; the reporting scheduler ticks export runs.
- **Recipient:** the export's configured recipient list (comma-joined).
- **Subject:** `[TesseraBX] Export ready: <export name>`.
- **Body:** hardcoded; export name, CBFS path, byte size, and either "the CSV is
  attached" or a download pointer to `/agent/admin/exports`. Event key
  `reporting.export.ready`. Optionally attaches the CSV (local-disk provider
  only; the S3 path is out of scope today).

### 3.3 Notification-driven emails (Path B), in detail

Three host events now have **email** templates seeded: `ticket.status_changed`
(agent + contact), `ticket.assigned` (agent, R1), and `ticket.message_added`
(agent only, R2). Every other host notification stays in-app only.

**8 and 9. Ticket status changed (agent and contact)**

- **Trigger:** when the tickets service changes a ticket's status it announces
  `onTicketStatusChanged`;
  [`TicketEventsInterceptor.onTicketStatusChanged`](modules_app/notifications/interceptors/TicketEventsInterceptor.bx)
  builds the recipient list (assigned agent and requester contact) and calls
  `dispatchForEvent("ticket.status_changed", ...)`.
- **Templates:** seeded by
  [`2026_05_15_001310_seed_email_notification_templates.cfc`](resources/database/migrations/2026_05_15_001310_seed_email_notification_templates.cfc):
  - Agent email: subject `Ticket #{{ticketNumber}} moved to {{to}}`, body
    `Ticket #{{ticketNumber}} ("{{subject}}") changed status from {{from}} to {{to}}.` plus an open link.
  - Contact email: subject `Your ticket #{{ticketNumber}} is now {{to}}`, body
    "We updated your ticket ... from {{from}} to {{to}}. If you need anything
    else, just reply to this email ..."
- **Delivery:** `EmailChannel.send()` looks up the recipient email (agents or
  contacts table), composes via `MailComposerService` with a per-recipient
  signed unsubscribe URL, and flips the `notifications` row to `sent` or `failed`.
- **Suppression:** a recipient who has opted out via `notification_preferences`
  for `(ticket.status_changed, email)` is skipped. Missing email on file marks
  the row `failed`.

**10. Ticket assigned (agent) (R1)**

- **Trigger:** when the tickets service reassigns a ticket it announces
  `onTicketAssigned` (a canonical envelope with `entity.id` and
  `before/after.assignedToAgentId`);
  [`TicketEventsInterceptor.onTicketAssigned`](modules_app/notifications/interceptors/TicketEventsInterceptor.bx)
  loads the ticket, skips unassignment and self-assignment, and dispatches
  `ticket.assigned` to the new assignee only.
- **Templates:** seeded by
  [`2026_06_06_000010_seed_ticket_assigned_notification_templates.cfc`](resources/database/migrations/2026_06_06_000010_seed_ticket_assigned_notification_templates.cfc)
  (in-app + email, agent recipient). Subject `Ticket #{{ticketNumber}} assigned
  to you`. No contact template (a client has no need to know which internal agent
  picked up the ticket).

**11. Customer-reply alert to agent (R2)**

- **Trigger:** when a **customer** (or accountless sender) adds a non-internal
  message, `onTicketMessageAdded` is announced and
  [`TicketEventsInterceptor.onTicketMessageAdded`](modules_app/notifications/interceptors/TicketEventsInterceptor.bx)
  targets the assigned agent (or all active agents). An **agent** reply instead
  targets the contact recipient, so this email never fires on an agent's own
  reply.
- **Templates:** the in-app agent template was already seeded; the email agent
  template was added by
  [`2026_06_06_000020_seed_ticket_message_added_agent_email_template.cfc`](resources/database/migrations/2026_06_06_000020_seed_ticket_message_added_agent_email_template.cfc).
  Subject `New reply on ticket #{{ticketNumber}}`. The `(ticket.message_added,
  email, contact)` tuple is still intentionally unseeded (see 3.4).

### 3.4 What still does not email through Path B (and why)

The no-double-send invariant remains intact for the two cases Path A already
owns:

- **`ticket.created`** has an **in-app** template only, seeded by
  [`2026_05_15_001220_seed_notification_templates.cfc`](resources/database/migrations/2026_05_15_001220_seed_notification_templates.cfc).
  Path A's auto-ack already emails the requester, so adding an email template here
  would double-send. The interceptor also skips internal notes, system-authored
  messages (the auto-ack), and the first non-system message on a ticket (so a new
  inbound-email ticket does not produce both a "created" and a "new reply"
  notification).
- **`ticket.message_added` on the contact side** is still email-free. An agent
  reply is delivered to the requester by Path A (`OutboundEmailService.sendAgentReply`);
  the interceptor keeps the contact only as an **in-app** recipient so the portal
  bell lights up without a duplicate email. R2 added an email only on the
  **agent** side (a customer reply), where Path A does not send anything.

---

## 4. Email catalog: tesserabx-pm add-on

### 4.1 Architecture

`tesserabx-pm` sends **no email directly**. It owns no `MailComposerService` call
and no SMTP configuration. Instead it declares notification templates in its
manifest and announces lifecycle events; a single interceptor maps each event to
recipients and calls the host `NotificationsService` (Path B). Delivery,
rendering, branding, unsubscribe, and the actual SMTP send are all the host's
job. PM email therefore inherits everything in section 2.

- **Templates:** declared in the `settings.tesserabx.notificationTemplates` array
  of [`tesserabx-pm/ModuleConfig.bx`](../tesserabx-pm/ModuleConfig.bx) (37 rows:
  17 email, 20 in-app, after the R8 additions). They register into the host's
  notification template registry at boot and are admin-editable like any host
  template.
- **Dispatcher:** [`tesserabx-pm/interceptors/PmNotificationDispatcher.bx`](../tesserabx-pm/interceptors/PmNotificationDispatcher.bx)
  listens for PM events and calls `NotificationsService.dispatchForEvent()`.
- **Recipient resolution:** assignee for assignment and due-date events; watchers
  (minus the actor) for comment, completion, and status-change events; the
  mentioned user for mentions; project watchers for project events and the
  **parent task's** watchers for subtask events (R8). Watchers come from
  `WatcherService@tesserabx-pm`.

### 4.2 PM email summary

| PM event | Email recipients | In-app recipients | Trigger | Sync vs scheduled |
|---|---|---|---|---|
| `tesserabx-pm.task_assigned` | agent, contact | agent, contact | Task created or reassigned (assignee set) | Inline (sync) |
| `tesserabx-pm.comment_added` | agent, contact | agent, contact | Comment posted on task/subtask/project (to watchers except author) | Inline (sync) |
| `tesserabx-pm.mentioned` | agent, contact | agent, contact | `@agent:` / `@contact:` mention parsed in a comment | Inline (sync) |
| `tesserabx-pm.task_completed` | agent only | agent | Task moved into a completed status (to watchers except actor) | Announced async |
| `tesserabx-pm.task_status_changed` | none (in-app only) | agent | Any task status change (to watchers except actor) | Inline (sync) |
| `tesserabx-pm.task_due_soon` | agent, contact | agent, contact | Due date within ~24h, detected by scheduler scan | Scheduler (every 15 min) |
| `tesserabx-pm.task_overdue` | agent, contact | agent, contact | Due date passed, detected by scheduler scan | Scheduler (every 15 min) |
| `tesserabx-pm.project_created` **(R8)** | agent, contact | agent, contact | A project is created (to project watchers except actor) | Inline (sync) |
| `tesserabx-pm.project_archived` **(R8)** | agent, contact | agent, contact | A project is archived (to project watchers except actor) | Inline (sync) |
| `tesserabx-pm.subtask_created` **(R8)** | none (in-app only) | agent, contact | A subtask is added (to the parent task's watchers except actor) | Inline (sync) |
| `tesserabx-pm.subtask_completed` **(R8)** | agent, contact | agent, contact | A subtask is completed (to the parent task's watchers except actor) | Inline (sync) |

Notes:

- `task_status_changed` and `subtask_created` are intentionally **in-app only**
  ("to keep email noise down").
- `task_completed` has an **agent email** template but no contact email template.
- Project events fan out to the project's watchers; subtask events fan out to the
  **parent task's** watchers (the audience already following the task), and the
  notification links back to the parent task detail page.
- A PM email actually ships only if the recipient has an email on file, has not
  opted out of that `(event, email)` tuple, and (for AI-gated surfaces, not
  relevant to these templates) the capability is enabled.

### 4.3 PM email templates (verbatim, from the manifest)

All bodies are single-line plain text; `{{appBaseUrl}}` and `{{unsubscribeUrl}}`
are injected by the host dispatcher.

| Event / recipient | Subject | Body |
|---|---|---|
| task_assigned / agent | `[PM] {{taskTitle}} assigned to you` | `{{actorLabel}} assigned you the task {{taskTitle}} in project {{projectName}}. Open the task: {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| task_assigned / contact | `[PM] {{taskTitle}} is on your plate` | `{{actorLabel}} assigned you the task {{taskTitle}} in {{projectName}}. Open it: {{appBaseUrl}}/pm/tasks/{{taskId}}` |
| comment_added / agent | `[PM] New comment on {{taskTitle}}` | `{{actorLabel}} left a comment on {{taskTitle}} (project {{projectName}}). Read it: {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| comment_added / contact | `[PM] New comment on {{taskTitle}}` | `{{actorLabel}} left a comment on {{taskTitle}} (project {{projectName}}). Read it: {{appBaseUrl}}/pm/tasks/{{taskId}}` |
| mentioned / agent | `[PM] {{actorLabel}} mentioned you` | `{{actorLabel}} mentioned you in a PM comment on {{taskTitle}} ({{projectName}}). Read it: {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| mentioned / contact | `[PM] {{actorLabel}} mentioned you` | `{{actorLabel}} mentioned you in a PM comment on {{taskTitle}} ({{projectName}}). Read it: {{appBaseUrl}}/pm/tasks/{{taskId}}` |
| task_completed / agent | `[PM] {{taskTitle}} complete` | `{{actorLabel}} marked {{taskTitle}} complete in {{projectName}}. {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| task_due_soon / agent | `[PM] {{taskTitle}} due {{dueDate}}` | `Your task {{taskTitle}} in {{projectName}} is due {{dueDate}}. Open: {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| task_due_soon / contact | `[PM] {{taskTitle}} due {{dueDate}}` | `Your task {{taskTitle}} in {{projectName}} is due {{dueDate}}. Open: {{appBaseUrl}}/pm/tasks/{{taskId}}` |
| task_overdue / agent | `[PM] {{taskTitle}} overdue` | `Your task {{taskTitle}} in {{projectName}} was due {{dueDate}} and remains open. Open: {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| task_overdue / contact | `[PM] {{taskTitle}} overdue` | `Your task {{taskTitle}} in {{projectName}} was due {{dueDate}} and remains open. Open: {{appBaseUrl}}/pm/tasks/{{taskId}}` |
| project_created / agent (R8) | `[PM] New project: {{projectName}}` | `{{actorLabel}} created the project {{projectName}}. Open it: {{appBaseUrl}}/agent/pm/projects/{{projectId}}` |
| project_created / contact (R8) | `[PM] New project: {{projectName}}` | `{{actorLabel}} created the project {{projectName}}. Open it: {{appBaseUrl}}/pm/projects/{{projectId}}` |
| project_archived / agent (R8) | `[PM] {{projectName}} archived` | `{{actorLabel}} archived the project {{projectName}}. {{appBaseUrl}}/agent/pm/projects/{{projectId}}` |
| project_archived / contact (R8) | `[PM] {{projectName}} archived` | `{{actorLabel}} archived the project {{projectName}}. {{appBaseUrl}}/pm/projects/{{projectId}}` |
| subtask_completed / agent (R8) | `[PM] Subtask complete: {{subtaskTitle}}` | `{{actorLabel}} completed the subtask {{subtaskTitle}} on {{taskTitle}} ({{projectName}}). {{appBaseUrl}}/agent/pm/tasks/{{taskId}}` |
| subtask_completed / contact (R8) | `[PM] Subtask complete: {{subtaskTitle}}` | `{{actorLabel}} completed the subtask {{subtaskTitle}} on {{taskTitle}} ({{projectName}}). {{appBaseUrl}}/pm/tasks/{{taskId}}` |

(`subtask_created` is in-app only, so it has no email row here.)

### 4.4 PM scheduler

[`tesserabx-pm/config/Scheduler.bx`](../tesserabx-pm/config/Scheduler.bx)
registers two tasks, gated to the scheduler container (`SCHEDULER_MODE=true`):

- `pm:scan-due-soon`, every 15 minutes, calls `PmTaskDueScanService.scanDueSoon()`.
- `pm:scan-overdue`, every 15 minutes, calls `PmTaskDueScanService.scanOverdue()`.

Each scan announces `onPmTaskDueSoon` / `onPmTaskOverdue` per matching task; the
dispatcher converts those into `task_due_soon` / `task_overdue` dispatches.
De-duplication state lives in `pm_task_notify_state` so the 15-minute cadence
does not re-notify the same task.

---

## 5. Workflow walkthroughs

Each workflow is an ordered trace of trigger to event to email(s). "Bell only"
means an in-app notification with no email.

### 5.1 New ticket from inbound email

1. The IMAP poller fetches a message; the inbound processor normalizes it and
   creates a ticket (often accountless) through the tickets service.
2. `onTicketCreated` is announced.
3. **Path A:** `OutboundEmailInterceptor` sends the **auto-acknowledgement**
   (email #1) to the sender, if `OUTBOUND_EMAIL_ENABLED` and the source is in the
   allowlist.
4. **Path B:** `TicketEventsInterceptor` dispatches `ticket.created` to the
   assigned agent (or all active agents if unassigned) and the requester. Only
   in-app templates exist, so this is **bell only** for agents; no email.
5. The inbound body is added as the first message; the interceptor recognizes it
   as the first non-system message and skips the `ticket.message_added` dispatch.

Net email: one auto-ack to the sender.

### 5.2 New guest submission via the portal contact form (unauthenticated)

1. The anonymous contact-form path calls `PendingTicketsService.createPending`.
2. **Email #3 (verification)** goes to the guest. No ticket exists yet.
3. The guest clicks the link; `confirmPending` creates an accountless ticket and
   first message.
4. `onTicketCreated` fires, producing the **auto-acknowledgement (email #1)** as
   in 5.1, plus the bell-only `ticket.created` notifications.

Net email: one verification, then one auto-ack on confirmation.

(An authenticated portal submission or a widget submission skips the verification
step and goes straight to the 5.1 pattern.)

### 5.3 New ticket created manually by an agent (dashboard)

1. The agent submits the new-ticket form; the tickets service creates the ticket
   with `source="agent"`.
2. `onTicketCreated` fires.
3. **Path A auto-ack is skipped** because `agent` is not in the auto-ack source
   allowlist.
4. **Path B:** `ticket.created` dispatches to the requester and the agent, **bell
   only** (no email template).

Net email: none. (If the agent then posts a public reply, see 5.4.)

### 5.4 Agent posts a public reply

1. The agent saves a public (non-internal) `TicketMessage`.
2. `onTicketMessageAdded` is announced.
3. **Path A:** `OutboundDispatchInterceptor` routes to the email adapter and
   `OutboundEmailService.sendAgentReply` emails the **reply (email #2)** to the
   requester, with threading headers.
4. **Path B:** `TicketEventsInterceptor` keeps the requester contact as an
   **in-app** recipient (bell), and deliberately does not email (no
   `ticket.message_added` email template).

Net email: one agent-reply email to the requester.

### 5.5 Contact or customer replies

By portal reply or by replying to the ticket email (inbound).

1. A contact-authored (or accountless-sender) `TicketMessage` is added.
2. `onTicketMessageAdded` is announced.
3. **Path A:** the dispatch reaches `OutboundEmailService.sendAgentReply`, which
   returns early because the message is not from an agent. No outbound email.
4. **Path B:** `TicketEventsInterceptor` notifies the assigned agent (or all
   active agents if unassigned) on **both** the bell and email (R2 seeded the
   agent email template), subject to per-recipient opt-out.

Net email: one customer-reply alert to the agent (**email #11**). The contact is
not emailed (they wrote the reply).

### 5.6 Ticket assignment or reassignment to an agent (R1)

1. The tickets service reassigns a ticket and announces `onTicketAssigned` (only
   when the assignee actually changes).
2. **Path B:** `TicketEventsInterceptor.onTicketAssigned` loads the ticket, skips
   unassignment and self-assignment, and dispatches `ticket.assigned` to the new
   assignee.
3. The new assignee gets a **bell and an email** (**email #10**), subject to
   opt-out.

Net email: one to the newly assigned agent (none when an agent assigns the ticket
to themselves).

### 5.7 Ticket status change, resolution, or close

1. The tickets service changes status and announces `onTicketStatusChanged`.
2. **Path B:** `TicketEventsInterceptor` dispatches `ticket.status_changed` to the
   assigned agent and the requester contact.
3. Both have **email templates**, so **emails #8 and #9** ship, subject to
   per-recipient opt-out, plus the matching bell rows.

Net email: up to one to the agent and one to the contact.

### 5.8 Internal note added

1. An agent saves a `TicketMessage` with `isInternal=true`.
2. `onTicketMessageAdded` is announced.
3. **Path A:** `OutboundDispatchInterceptor` skips internal messages; even if it
   did not, `OutboundEmailService.sendAgentReply` also guards on `isInternal`.
4. **Path B:** `TicketEventsInterceptor` returns early on internal messages.

Net email: none, by design and by defense in depth. Internal notes never reach
any client-side recipient.

### 5.9 Member invite and activation

1. An Organization Admin invites a member; `ContactInviteService.invite` sends
   the **invite (email #4)**.
2. The member clicks the set-password link and activates. No further email.

### 5.10 Agent changes their email address

1. The agent requests an email change in My Account; **email #5 (verification)**
   goes to the new address.
2. The agent clicks the 60-minute link to confirm. No further email.

### 5.11 Contact password reset (R3)

1. A signed-out contact submits `/forgot-password`;
   `Session.forgotPasswordSubmit` calls `ContactInviteService.requestPasswordReset`.
2. If the email matches a contact, a short-lived `reset`-purpose token is written
   and **email #12** is sent with a `/set-password?reset=1&token=...` link. If the
   email is unknown, nothing is sent (the handler shows the same neutral message
   either way).
3. The contact follows the link and sets a new password through the existing
   `/set-password` consume path. No further email.

Net email: one reset link (only when the address has an account).

### 5.12 Agent password reset (R3)

1. A signed-out agent submits `/agent/forgot-password`;
   `agent/Session.forgotPasswordSubmit` calls `AgentService.requestPasswordReset`.
2. If the email matches an agent, a short-lived token (in `agent_password_tokens`)
   is written and **email #13** is sent with an `/agent/reset-password?token=...`
   link. Unknown email is a neutral no-op.
3. The agent follows the link and sets a new password. MFA is untouched, so the
   next sign-in still challenges for the authenticator code.

Net email: one reset link (only when the address has an account).

### 5.13 Scheduled report export

1. The reporting scheduler runs a due export, writes the CSV to CBFS, and calls
   `sendReadyEmail`.
2. **Email #7** goes to the configured recipients, optionally with the CSV
   attached.

### 5.14 PM: task assigned

1. A task is created with an assignee, or an existing task is reassigned.
2. `onPmTaskAssigned` is announced; the dispatcher resolves the assignee and
   dispatches `tesserabx-pm.task_assigned` (self-assignment is suppressed).
3. The assignee gets an **email and a bell** (agent or contact templates).

### 5.15 PM: comment added

1. A comment is posted on a task, subtask, or project.
2. `onPmCommentAdded` fires; the dispatcher fans out to every watcher except the
   author and dispatches `tesserabx-pm.comment_added`.
3. Each watcher gets an **email and a bell**.
4. If the comment contains `@agent:` / `@contact:` mentions, `MentionService`
   separately announces `onPmMentioned`, producing a **mention email and bell**
   for each mentioned user (in addition to the comment notification).

### 5.16 PM: task completed or status changed

1. A task status change announces `onPmTaskCompleted` (entering a completed
   status) and/or `onPmTaskStatusChanged`.
2. `task_completed` emails agent watchers (bell for agents); contacts get bell
   only (no contact template).
3. `task_status_changed` is **bell only** for all watchers (no email template).

### 5.17 PM: task due soon or overdue

1. Every 15 minutes the scheduler scans tasks crossing the due-soon / overdue
   thresholds (deduped via `pm_task_notify_state`).
2. Matching tasks announce `onPmTaskDueSoon` / `onPmTaskOverdue`; the dispatcher
   notifies the assignee.
3. The assignee gets an **email and a bell**.

### 5.18 PM: project created or archived (R8)

1. `ProjectService` creates or archives a project and announces
   `onPmProjectCreated` / `onPmProjectArchived` (sync).
2. `PmNotificationDispatcher.projectWatcherDispatch` resolves the project's
   watchers (minus the actor) and dispatches `project_created` /
   `project_archived`.
3. Each project watcher gets an **email and a bell**. If nobody watches the
   project, nobody is notified.

### 5.19 PM: subtask created or completed (R8)

1. `SubtaskService` creates or completes a subtask and announces
   `onPmSubtaskCreated` / `onPmSubtaskCompleted` (sync).
2. `PmNotificationDispatcher.subtaskWatcherDispatch` loads the subtask, resolves
   the **parent task's** watchers (minus the actor), and dispatches the event.
3. For `subtask_completed`, each watcher gets an **email and a bell**;
   `subtask_created` is **bell only** (no email template). The link points at the
   parent task detail page.

---

## 6. Template and layout reference

### 6.1 HTML layout wrappers (both paths, both apps)

| Style | View | Used by |
|---|---|---|
| `notification` (full chrome) | [modules_app/core/views/emails/default_layout.bxm](modules_app/core/views/emails/default_layout.bxm) | All notification mail, verifications, invites, exports, test, status-change, all PM mail |
| `reply` (thin chrome) | [modules_app/core/views/emails/default_layout_reply.bxm](modules_app/core/views/emails/default_layout_reply.bxm) | Ticket auto-ack and agent reply when the org opts into reply chrome |

In-code fallback: `MailComposerService.placeholderLayout()` (only if view
rendering is unavailable at boot).

### 6.2 Notification template content (Path B), where it lives

| Source | Event keys covered | Channels |
|---|---|---|
| [seed_notification_templates.cfc](resources/database/migrations/2026_05_15_001220_seed_notification_templates.cfc) | `ticket.created`, `ticket.message_added`, `ticket.status_changed` | inapp (agent + contact) |
| [seed_email_notification_templates.cfc](resources/database/migrations/2026_05_15_001310_seed_email_notification_templates.cfc) | `ticket.status_changed` | email (agent + contact) |
| [seed_ticket_assigned_notification_templates.cfc](resources/database/migrations/2026_06_06_000010_seed_ticket_assigned_notification_templates.cfc) **(R1)** | `ticket.assigned` | inapp + email (agent) |
| [seed_ticket_message_added_agent_email_template.cfc](resources/database/migrations/2026_06_06_000020_seed_ticket_message_added_agent_email_template.cfc) **(R2)** | `ticket.message_added` | email (agent) |
| [tesserabx-pm/ModuleConfig.bx](../tesserabx-pm/ModuleConfig.bx) `notificationTemplates` | the eleven `tesserabx-pm.*` events (seven task/comment/mention + four project/subtask from R8) | inapp + email (see 4.3) |

All notification template content is stored as rows in `notification_templates`
(DB is the source of truth; the in-code registry is the fallback and the add-on
contribution path). Rows are admin-editable.

### 6.3 Direct-send bodies (Path A), where they live

These subjects and bodies are hardcoded in the service method, not in a template
file or the DB.

| Email | Body location |
|---|---|
| Auto-ack | `autoAckBody()` in [OutboundEmailService.bx](modules_app/channels/models/OutboundEmailService.bx) |
| Agent reply | the agent's message body (no template) |
| Guest verification | `sendVerificationEmail()` in [PendingTicketsService.bx](modules_app/portal/models/PendingTicketsService.bx) |
| Member invite | `sendInviteEmail()` in [ContactInviteService.bx](modules_app/contacts/models/ContactInviteService.bx) |
| Agent email change | `sendVerificationEmail()` in [MyAccount.bx](modules_app/agent/wires/MyAccount.bx) |
| Admin test | `testEmail()` in [admin/Settings.bx](modules_app/agent/modules/admin/handlers/Settings.bx) |
| Export ready | `sendReadyEmail()` in [ScheduledExportService.bx](modules_app/reporting/models/ScheduledExportService.bx) |
| Contact password reset (R3) | `sendResetEmail()` in [ContactInviteService.bx](modules_app/contacts/models/ContactInviteService.bx) |
| Agent password reset (R3) | `sendResetEmail()` in [AgentService.bx](modules_app/agent/models/AgentService.bx) |

### 6.4 Placeholder tokens

- Host ticket templates: `{{ticketNumber}}`, `{{subject}}`, `{{status}}`,
  `{{from}}`, `{{to}}`, `{{ticketId}}`, `{{authorLabel}}`, plus `{{appBaseUrl}}`
  and `{{unsubscribeUrl}}` injected by the dispatcher.
- PM templates: `{{actorLabel}}`, `{{taskTitle}}`, `{{projectName}}`,
  `{{dueDate}}`, `{{taskId}}`, plus `{{appBaseUrl}}` and `{{unsubscribeUrl}}`.
- Unknown tokens are left in place by the renderer (so a typo surfaces rather
  than silently blanking).

---

## 7. Gaps and silent paths

### 7.1 Resolved since the original audit

| Area | Resolution |
|---|---|
| Ticket assignment / reassignment | **R1**: `onTicketAssigned` now dispatches `ticket.assigned` to the new agent (in-app + email); self-assignment and unassignment are skipped. |
| Customer reply to agent | **R2**: `ticket.message_added` now emails the **agent** on a customer reply; the contact side stays email-free (no double-send). |
| Contact password reset | **R3**: `/forgot-password` issues a `reset`-purpose token and emails a `/set-password` link; neutral no-op for unknown emails. |
| Agent password reset | **R3**: `/agent/forgot-password` issues a token (`agent_password_tokens`) and emails an `/agent/reset-password` link; MFA untouched. |
| PM project / subtask events | **R8**: `PmNotificationDispatcher` now handles `onPmProjectCreated/Archived` and `onPmSubtaskCreated/Completed` with 14 new manifest templates. |
| Stale `AUTO_ACK_ENABLED` comment | **R7**: corrected to reference `OUTBOUND_EMAIL_ENABLED` (the real gate). |

### 7.2 Still open

Events announced or workflows that exist but produce **no email** today. Each is
evidence-backed, not speculation.

| Area | State | Evidence |
|---|---|---|
| Approval request / approve / reject | Approval events are announced but **no listener and no templates**. | No approval handlers in the notifications interceptor; no approval template seeds. |
| SLA breach / breach warning / escalation | Tracked in the `sla` module but **no notification listener or template**, so no email. | No `onSla*` handler or template seed. |
| Automation actions | The rules engine has no **send-email** action executor. | Action executors cover status, priority, assignment, and approval only. |
| MFA enrollment / recovery codes | Recovery codes are shown in-app at enrollment; **none are emailed**. | MFA setup stores and displays codes; no compose call. |
| Account lockout | No lockout-notification email. | No lockout send site. |
| Knowledgebase | Article publish and feedback are recorded but **no email**. | No KB notification listener or template. |
| New ticket to agent | Agent is alerted **in-app only** (intentional); no email. | `ticket.created` has an in-app template only (3.4). |
| Slack / Teams channel | A `SlackChannel` exists and routes on `SLACK_WEBHOOK_URL`, but it is a webhook, not email. | Out of scope for an email audit; noted for completeness. |
| Webhooks (`api`) | `ticket.*` events are forwarded to external webhooks (outbound HTTP), not email. | Webhook dispatch interceptor; external systems may email downstream. |

New-ticket-to-agent being bell-only is an intentional design choice (the auto-ack
already emails the requester via Path A), not a defect, but it is worth surfacing
because an operator may expect email there.

---

## 8. Findings and recommendations

### 8.1 Observations

- **F1. The two-path split is deliberate and well-guarded.** The notification
  interceptor and the email-template seeds go out of their way to prevent
  double-sending. The invariant is one email owner **per recipient**: after R2,
  `ticket.message_added` emails the agent on a customer reply while the contact
  side stays with Path A, so neither party is emailed twice.
- **F2. All email is synchronous.** Nothing rides cbq. This is consistent with
  the known cbq-on-Postgres limitation in this project. It is fine for low
  volume, but a slow SMTP server will block the originating request (auto-ack and
  agent reply send inline during the ticket write). The per-send try/catch keeps
  a failure from breaking the ticket, but not from adding latency.
- **F3. Branding, From, unsubscribe, and ops headers are consistent** because
  every path funnels through `MailComposerService`. Notification mail carries a
  signed one-click `List-Unsubscribe`; ticket replies (reply style) intentionally
  do not.
- **F4. PM is a clean Path B consumer.** It adds no new mail mechanics, only
  templates and event announces, and correctly relies on the host for delivery,
  preferences, and unsubscribe.
- **F5. Some announced events still have no consumer.** Assignment was wired by
  R1, but the **approval** and **SLA breach** events are still announced into the
  void, a latent ready-to-wire surface rather than a bug.
- **F6. Stale comment (resolved).** [OutboundEmailService.bx](modules_app/channels/models/OutboundEmailService.bx)
  previously referenced a non-existent `AUTO_ACK_ENABLED` flag; R7 corrected the
  comment to `OUTBOUND_EMAIL_ENABLED` (the real, shared gate).

### 8.2 Recommendations

**Status at a glance** (updated 2026-06-06):

| Rec | Status |
|---|---|
| R1 (assignment notifications) | **Done** |
| R2 (customer-reply-to-agent email) | **Done** |
| R3 (contact + agent password reset) | **Done** |
| R7 (fix stale comment) | **Done** |
| R8 (PM project/subtask templates) | **Done** (in `tesserabx-pm`) |
| R4 (approval + SLA notifications) | Open |
| R5 (send-email automation action) | Open |
| R6 (move email onto cbq) | Deferred (blocked by cbq-on-Postgres; Phase 6) |

- **R1 (medium) — Done.** `TicketEventsInterceptor.onTicketAssigned` dispatches
  `ticket.assigned` to the newly assigned agent (in-app + email templates seeded);
  self-assignment and unassignment are skipped.
- **R2 (medium) — Done.** A `(ticket.message_added, email, agent)` template now
  emails the assigned agent on a customer reply. The contact side stays email-free
  to preserve the no-double-send invariant (the contact already gets the agent
  reply via Path A).
- **R3 (medium) — Done.** Self-service password reset for both account families:
  `/forgot-password` (contact, reuses `/set-password`) and `/agent/forgot-password`
  + `/agent/reset-password` (agent, new `agent_password_tokens` table). Tokens are
  short-lived (`PASSWORD_RESET_TTL_HOURS`, default 2), the request is a neutral
  no-op for unknown addresses, and agent MFA is untouched.
- **R4 (low) — Open.** Wire approval and SLA-breach notifications. The events are
  announced (`onTicketApproval*`, `onSlaBreachWarning`, `onSlaBreached`); add
  listeners and templates when those features need to reach a human.
- **R5 (low) — Open.** Consider a send-email automation action. The rules engine
  cannot email today; an action executor that dispatches a templated notification
  would let operators build custom email automations.
- **R6 (low) — Deferred.** Move email onto cbq once the Postgres queue issue is
  resolved (Phase 6 owns that fix). `MailComposerService.send()` is already the
  chokepoint the docblock earmarks for queueing; async delivery would remove SMTP
  latency from the request path (see F2).
- **R7 (trivial) — Done.** The stale `AUTO_ACK_ENABLED` comment now reads
  `OUTBOUND_EMAIL_ENABLED`.
- **R8 (low) — Done.** `PmNotificationDispatcher` handles
  `onPmProjectCreated/Archived` and `onPmSubtaskCreated/Completed`, with 14 new
  manifest templates (project + subtask_completed get inapp + email; subtask_created
  is inapp only). Shipped on a `tesserabx-pm` feature branch.

---

## Appendix: complete email index

| Email | App | Path | Event key | Template / body location |
|---|---|---|---|---|
| Ticket auto-acknowledgement | host | A | `tickets.auto_ack` | OutboundEmailService `autoAckBody()` |
| Agent reply | host | A | `tickets.agent_reply` | agent message body |
| Guest verification | host | A | `portal.pending_ticket.verify` | PendingTicketsService |
| Member invite | host | A | `portal.member_invite.set_password` | ContactInviteService |
| Agent email-change verification | host | A | `account.email_change.verify` | MyAccount wire |
| Admin test | host | A | `system.test` | admin Settings handler |
| Export ready | host | A | `reporting.export.ready` | ScheduledExportService |
| Ticket status changed (agent) | host | B | `ticket.status_changed` | seed_email_notification_templates.cfc |
| Ticket status changed (contact) | host | B | `ticket.status_changed` | seed_email_notification_templates.cfc |
| Ticket assigned (agent) **(R1)** | host | B | `ticket.assigned` | seed_ticket_assigned_notification_templates.cfc |
| Customer-reply alert to agent **(R2)** | host | B | `ticket.message_added` | seed_ticket_message_added_agent_email_template.cfc |
| Contact password reset **(R3)** | host | A | `portal.password_reset.request` | ContactInviteService `sendResetEmail` |
| Agent password reset **(R3)** | host | A | `agent.password_reset.request` | AgentService `sendResetEmail` |
| Task assigned (agent, contact) | pm | B | `tesserabx-pm.task_assigned` | tesserabx-pm ModuleConfig |
| Comment added (agent, contact) | pm | B | `tesserabx-pm.comment_added` | tesserabx-pm ModuleConfig |
| Mentioned (agent, contact) | pm | B | `tesserabx-pm.mentioned` | tesserabx-pm ModuleConfig |
| Task completed (agent) | pm | B | `tesserabx-pm.task_completed` | tesserabx-pm ModuleConfig |
| Task due soon (agent, contact) | pm | B | `tesserabx-pm.task_due_soon` | tesserabx-pm ModuleConfig |
| Task overdue (agent, contact) | pm | B | `tesserabx-pm.task_overdue` | tesserabx-pm ModuleConfig |
| Project created (agent, contact) **(R8)** | pm | B | `tesserabx-pm.project_created` | tesserabx-pm ModuleConfig |
| Project archived (agent, contact) **(R8)** | pm | B | `tesserabx-pm.project_archived` | tesserabx-pm ModuleConfig |
| Subtask completed (agent, contact) **(R8)** | pm | B | `tesserabx-pm.subtask_completed` | tesserabx-pm ModuleConfig |

In-app-only notifications (no email, listed for completeness): host
`ticket.created`; the contact side of host `ticket.message_added`; PM
`task_status_changed` and `subtask_created`; the contact side of PM
`task_completed`.
