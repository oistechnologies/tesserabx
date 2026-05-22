## Automation: triggers, conditions, and actions

The automation engine evaluates rules of the form *"when TRIGGER fires AND all CONDITIONS pass, run ACTIONS"*. Phase 6 makes each of the three vocabularies extensible.

Four registries cover the engine surface:

| Registry                                | Purpose                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------- |
| `TriggerRegistry@automation`            | The event keys a rule's `trigger` column can reference.                   |
| `OperatorRegistry@automation`           | The comparators a condition's `op` can use (`eq`, `gt`, `in`, ...).        |
| `ConditionFieldRegistry@automation`     | The fields a condition's `field` can reference (`priority`, `status`, ...). |
| `ActionRegistry@automation`             | The actions a rule can execute, plus parameter schemas and executor classes. |

Core seeds three triggers (`ticket.created`, `ticket.status_changed`, `ticket.escalation`), twelve operators, ~14 fields, and four actions (`setPriority`, `setStatus`, `assignToAgent`, `assignByStrategy`). Every add-on contribution appears next to core's seeds.

### Declaring a trigger

```boxlang
settings.tesserabx.automationTriggers = [
    {
        id          : "kb.article_published",
        label       : "Knowledge-base article published",
        description : "Fires when an article reaches the published state.",
        eventName   : "onKbArticlePublished"
    }
];
```

The `eventName` is the ColdBox interception point the trigger listens on. The add-on is responsible for shipping the listener that calls `AutomationService.evaluateForTicket( "kb.article_published", articleEntity, eventData )` (or an equivalent for non-ticket entities once the engine generalizes).

### Declaring an operator

```boxlang
settings.tesserabx.automationOperators = [
    {
        id          : "matchesRegex",
        label       : "matches regex",
        description : "RHS is a regular expression matched against the LHS string value.",
        valueShape  : "string",
        evaluator   : "RegexOperatorEvaluator@compliance"
    }
];
```

Core operators are inlined in `AutomationService.conditionPasses`; their `evaluator` is `""`. Add-on operators implement an `evaluate( fieldName, op, lhs, rhs )` method on the executor class registered at the `evaluator` mapping; the service resolves and calls it during condition evaluation.

### Declaring a condition field

```boxlang
settings.tesserabx.automationFields = [
    {
        id          : "ticket.tags",
        label       : "Tag",
        description : "Any tag currently attached to the ticket.",
        type        : "string",
        appliesTo   : []   // empty = universal across triggers
    }
];
```

`appliesTo` scopes the field to specific triggers. Empty or absent means universal.

### Declaring an action

```boxlang
settings.tesserabx.automationActions = [
    {
        id              : "slack.postToChannel",
        label           : "Post to Slack channel",
        description     : "Notify a Slack channel when the rule fires.",
        executor        : "SlackPostExecutor@example-slack",
        parameterSchema : [
            { name : "value", label : "Channel", type : "string", required : true, placeholder : "##incidents" }
        ]
    }
];
```

The executor class must implement:

```boxlang
public struct function execute( required struct action, required any ticket, required any rule ){
    // returns { type, value, [skipped, reason, ...] }
}
```

`AutomationService` resolves the executor through `ActionRegistry.dispatch( action, ticket, rule )` and returns whatever the executor returns. Action results land in the rule-fires log.

### Parameter schema

Each action declares its own parameter schema as a list of field descriptors:

| Field         | Notes                                                              |
| ------------- | ------------------------------------------------------------------ |
| `name`        | The key the form submits.                                          |
| `label`       | Human label for the rule editor.                                   |
| `type`        | `"string"` \| `"select"` \| `"boolean"` \| `"textarea"` \| `"number"` |
| `required`    | Defaults to false.                                                 |
| `options`     | Array of strings (for `type=select`).                              |
| `placeholder` | Optional placeholder text.                                         |
| `description` | Optional help text.                                                |

**Storage note**: rules currently persist a single `value` per action (`{ type : "setPriority", value : "high" }`). Multi-field schemas (Slack: channel + message) land when the rule editor's action form migrates from `{ type, value }` to `{ type, params : { ... } }`. Until then, add-on action schemas should stick to a single `name : "value"` descriptor so they round-trip through the existing storage.

### Migration impact

Existing automation rules in the database (`{ type : "setPriority", value : "high" }`) continue to evaluate identically: `ActionRegistry.dispatch` resolves the executor by id and calls it with the same arguments the previous switch-case received. The four core action executors (`SetPriorityExecutor`, `SetStatusExecutor`, `AssignToAgentExecutor`, `AssignByStrategyExecutor`) wrap the exact code that previously lived in `AutomationService.applyOne`.

`AutomationService.listSupportedTriggers / listSupportedOps / listSupportedActions` now return registry-backed arrays, so add-on contributions automatically appear in any UI that listed the previous hard-coded constants.

---

