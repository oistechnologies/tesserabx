# sla

SLA policies and business-hours calendars, plus the math that converts
them into wall-clock deadlines.

See [CLAUDE.md](../../CLAUDE.md) for hard constraints and
[docs/BUILD-PLAN.md](../../docs/BUILD-PLAN.md) for the phased build order.

## Owned entities

- **BusinessHoursCalendar** — weekly hours, holiday list, and a timezone.
  Not tenant-scoped; provider configuration.
- **SlaPolicy** — first-response and resolution targets, scoped by
  ticket priority and / or organization tier. Belongs to one
  BusinessHoursCalendar (falls back to the default calendar when none
  is named). Not tenant-scoped.

## Public service interface

`SlaService@sla` (singleton):

- `listCalendars()`, `getCalendarById(id)`, `getDefaultCalendar()`,
  `createCalendar(data)`, `updateCalendar(id, data)`,
  `getWeeklyHoursFor(cal)`, `getHolidaysFor(cal)`
- `listPolicies()`, `getPolicyById(id)`, `createPolicy(data)`
- `matchPolicyForTicket(ticket)` — picks the most-specific active
  policy. Ranking: priority + tier beats priority-only beats tier-only
  beats catch-all; ties break on `precedence` descending and finally
  on `is_default`.
- `computeFirstResponseDeadline(ticket, policy)` /
  `computeResolutionDeadline(ticket, policy)` — return a
  `java.time.Instant`. Phase 3b wires these into the ticket lifecycle.
- `addBusinessMinutes(startInstant, minutes, calendar)` — timezone-aware
  business-time math, skipping nights, weekends, and configured
  holidays.
- `toInstant(value)` / `formatInstantUtc(instant)` — date conversion
  helpers used at the persistence boundary.

## Events emitted

None yet. Phase 3b will introduce `onSlaBreachWarning` and related
points as the scheduler comes online.
