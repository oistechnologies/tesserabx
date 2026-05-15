# automation

Trigger-condition-action rules engine. Listens to the tickets module's
custom interception points, picks every active rule whose `trigger`
matches, evaluates conditions against the ticket, and runs the rule's
actions in declared order.

See [CLAUDE.md](../../CLAUDE.md) for hard constraints and
[docs/BUILD-PLAN.md](../../docs/BUILD-PLAN.md) for the phased build order.

## Owned entities

- **AutomationRule** — one rule (trigger + conditions + actions +
  precedence + is_active). conditions/actions are JSON text.
  Provider-side configuration, not tenant-scoped.
- **RecurringTicketTemplate** — describes a ticket the scheduler
  creates on a cadence (subject, body, priority, type, plus
  assignment / org / contact targets and an interval_minutes
  schedule). Materialized into a real Ticket by
  `RecurringTicketService.runTemplate`.

Also owns the `assignment_state` key-value table that persists
round-robin pointers across restarts.

## Public service interface

`AutomationService@automation` (singleton):

- `listRules()` / `listRulesForTrigger(trigger)` / `getRule(id)`
- `createRule(data)` / `updateRule(id, data)` / `deleteRule(id)`
- `evaluateForTicket(trigger, ticket [, eventData])` — synchronous;
  fires every matching active rule's actions in precedence order. The
  trigger string matches the persisted `trigger` column.
- `matches(rule, ticket [, eventData])` — pure boolean; specs use this
  for condition-evaluation coverage without action side effects.
- `listSupportedTriggers()` / `listSupportedOps()` /
  `listSupportedActions()` — convenience lists for the admin UI in
  Phase 5.

`AssignmentService@automation` (singleton):

- `listStrategies()` — `[ "roundRobin", "leastLoaded" ]`
- `pickAgent(strategy [, strategyKey])` — returns the chosen agent
  id or `""` when no eligible agent exists. `strategyKey` scopes the
  round-robin pointer (default `"default"`); when teams land in
  Phase 5 the key will be the team id.
- `listEligibleAgentIds()` — the active-agent population the
  strategies pick from.

`RecurringTicketService@automation` (singleton):

- `listTemplates()` / `getTemplate(id)` / `createTemplate(data)` /
  `updateTemplate(id, data)` / `deleteTemplate(id)`
- `listDueTemplates()` — active templates with `next_run_at <= NOW()`
  or null. The Phase 3e scheduler iterates this list.
- `runTemplate(id)` — materializes one ticket from the template and
  advances `next_run_at` by `intervalMinutes`. Returns the new Ticket.

## Triggers

- `ticket.created` — both contact-backed and accountless creates
- `ticket.status_changed` — `eventData` carries `from` and `to`
- `ticket.escalation` — fired by the Phase 3e scheduler on each
  active ticket so time-based escalation rules can match

## Conditions

A rule's `conditions` is a JSON array; all entries must pass (AND).
Each entry is `{ field, op, value }`.

Supported fields:

- `priority`, `status`, `ticketType`, `source`, `subject`,
  `organizationId`, `requesterContactId`, `originatingEmail`,
  `isAccountless`
- `from` / `to` — only meaningful for `ticket.status_changed`
- `minutesSinceCreated`, `minutesSinceFirstResponseDue`,
  `minutesSinceResolutionDue`, `hasFirstResponse` — for time-based
  escalation rules; the duration fields are negative while the
  deadline is still in the future

Supported ops: `eq`, `neq`, `contains`, `notContains`, `in`, `notIn`,
`isEmpty`, `isNotEmpty`, `gt`, `gte`, `lt`, `lte`.

## Actions

- `setPriority` — direct setter + save
- `setStatus` — calls `TicketsService.changeStatus` (respects the
  status transition table and SLA pause/resume math)
- `assignToAgent` — calls `TicketsService.assignToAgent`
- `assignByStrategy` — value is `"roundRobin"` or `"leastLoaded"`;
  delegates to `AssignmentService.pickAgent` then assigns

A thread-local re-entrancy guard short-circuits nested automation
evaluation so an action-initiated status change cannot re-fire the
same rule chain.

## Events emitted

None yet. The interception points fire from `tickets` and channels'
outbound dispatch; this module is purely a consumer.
