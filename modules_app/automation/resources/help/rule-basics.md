## Automation rule basics

Automation rules let TesseraBX react to ticket events without an agent in the loop. A rule has three parts:

1. **A trigger** - the event that fires the rule (e.g. `ticket.created`, `ticket.status_changed`, `ticket.escalation`).
2. **Zero or more conditions** - predicates over the ticket that must all be true for the rule to apply. An empty list matches every ticket the trigger sees.
3. **One or more actions** - what to do when the rule applies (set priority, set status, assign to an agent, route by strategy, plus any add-on actions).

### Building a rule

Open **Automation rules** under /agent/admin and click **New rule**. The editor pulls its trigger, field, operator, and action options from the registries, so add-on contributions appear automatically:

- The **trigger** dropdown lists every entry in `TriggerRegistry`.
- The **condition** field dropdown lists fields from `ConditionFieldRegistry` that apply to the selected trigger.
- The **condition** operator dropdown lists every entry in `OperatorRegistry`. The value input shape (text, number, comma-separated list, or none) follows the operator's declared `valueShape`.
- The **action** dropdown lists every entry in `ActionRegistry`. When you pick an action, its `parameterSchema` renders as a form below the picker.

### Action parameter shape

Each action persists as `{ type, params : { ... } }`. The four built-in core actions use a single `value` parameter:

| Action id           | params       | Meaning                                                   |
| ------------------- | ------------ | --------------------------------------------------------- |
| `setPriority`       | `{ value }`  | One of `low`, `normal`, `high`, `urgent`.                 |
| `setStatus`         | `{ value }`  | A status key from the workflow editor.                    |
| `assignToAgent`     | `{ value }`  | UUID of the agent. Empty unassigns.                       |
| `assignByStrategy`  | `{ value }`  | `roundRobin` or `leastLoaded`.                            |

Add-on actions can declare multiple parameters in their schema; each becomes a form input in the editor and a key under `params` on disk.

The engine accepts the legacy `{ type, value }` shape produced by rules created before the editor shipped; `AutomationService.normalizeAction` wraps that form into the new shape on read.

### Order of evaluation

Within a trigger, rules run in descending **precedence**. Ties run alphabetically by name. Every matching rule's actions run in declared order. The re-entry guard inside `AutomationService` keeps a rule whose action causes a follow-up event (for example `setStatus` firing `ticket.status_changed`) from looping back into itself on the same request.
