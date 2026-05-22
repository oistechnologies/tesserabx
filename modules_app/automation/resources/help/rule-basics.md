## Automation rule basics

Automation rules let TesseraBX react to ticket events without an agent in the loop. A rule has three parts:

1. **A trigger** — the event that fires the rule (e.g. `ticket.created`, `ticket.status_changed`).
2. **Zero or more conditions** — predicates over the ticket that must all be true for the rule to apply.
3. **One or more actions** — what to do when the rule applies (assign to an agent, set priority, post a Slack message).

### Building a rule

Open **Workflow** -> **Automation** under /agent/admin and click **New rule**. Pick a trigger, add conditions, pick actions, and save. Conditions and actions render their parameter forms from the registry so new add-on actions appear automatically.

### Order of evaluation

Rules with a lower **sort weight** run first. When multiple rules match the same event, every matching rule runs in order. To stop the chain, an action can mark the rule as **terminal**.

### Testing a rule

Use the **Dry run** button on the rule editor to evaluate the rule against an existing ticket without applying side effects. The dry-run report shows which conditions matched and which actions would have fired.
