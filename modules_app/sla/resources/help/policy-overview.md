## SLA policy overview

A **service-level agreement (SLA) policy** sets the response and resolution targets that a ticket must meet. The system tracks elapsed time against the policy and warns or escalates as those targets approach.

### Anatomy of a policy

| Field                        | What it controls                                                              |
| ---------------------------- | ----------------------------------------------------------------------------- |
| `first_response_minutes`     | How long the first agent reply may take after the ticket is created.          |
| `resolution_minutes`         | How long until the ticket must be resolved.                                   |
| `business_hours_calendar_id` | The schedule the clock follows (working hours, holidays, time zone).          |
| `precedence`                 | Lower wins when multiple policies could match the same ticket.                |
| `is_default`                 | The catch-all when no other policy matches.                                   |

### Matching

A new ticket is matched to a policy based on its `priority`, `tier`, and the organization's configured policy if any. Matching runs once at create time and again when priority or tier changes. The currently-applied policy is shown in the right column of every ticket.

### Pause and resume

A ticket in **Waiting on customer** automatically pauses the SLA clock; it resumes when the requester replies. Internal notes do not affect the clock.

### Breach handling

When a ticket exceeds its first-response or resolution target, the system fires `onSlaBreached`. The notifications module sends a configurable alert; automation rules can route the ticket or escalate priority.
