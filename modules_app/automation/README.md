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

## Triggers (Phase 3c)

- `ticket.created` — both contact-backed and accountless creates
- `ticket.status_changed` — `eventData` carries `from` and `to`

## Conditions

A rule's `conditions` is a JSON array; all entries must pass (AND).
Each entry is `{ field, op, value }`.

Supported fields:

- `priority`, `status`, `ticketType`, `source`, `subject`,
  `organizationId`, `requesterContactId`, `originatingEmail`,
  `isAccountless`
- `from` / `to` — only meaningful for `ticket.status_changed`

Supported ops: `eq`, `neq`, `contains`, `notContains`, `in`, `notIn`,
`isEmpty`, `isNotEmpty`.

## Actions (Phase 3c)

- `setPriority` — direct setter + save
- `setStatus` — calls `TicketsService.changeStatus` (respects the
  status transition table and SLA pause/resume math)
- `assignToAgent` — calls `TicketsService.assignToAgent`

A thread-local re-entrancy guard short-circuits nested automation
evaluation so an action-initiated status change cannot re-fire the
same rule chain.

## Events emitted

None yet. Phase 3d adds escalation and recurring rules, and the
interception points fire from this module then.
