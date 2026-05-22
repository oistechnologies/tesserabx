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

Core operators are inlined in `AutomationService.conditionPasses`; their `evaluator` is `""`. Add-on operators implement the `IOperatorEvaluator` contract (see `modules_app/automation/models/contracts/IOperatorEvaluator.bx`) by exposing:

```boxlang
public boolean function evaluate(
    required string field,
    required string op,
    required any    lhs,
    required any    rhs
){
    // return true when the operator's predicate holds against the ticket
}
```

WireBox singletons are the standard shape. `AutomationService.conditionPasses` looks up the operator entry in the registry, resolves the `evaluator` mapping at evaluation time, and calls `evaluate` with the field id, the operator id, the value the ticket actually carries for that field (LHS), and the operand the rule stored alongside it (RHS).

Failure modes are intentionally silent at the rule level so a broken add-on operator cannot crash the engine, but they surface in the `Automation` log file:

- An unknown operator id: condition resolves to false, one log line per evaluation.
- An operator registered without an `evaluator` mapping: condition resolves to false with a warning.
- An evaluator that throws: condition resolves to false with the exception message.

`valueShape` (`"string"` \| `"number"` \| `"list"` \| `"none"`) drives the rule editor's value input shape, not the engine. Pick the shape that matches what RHS will be on disk.

### Declaring a condition field

```boxlang
settings.tesserabx.automationFields = [
    {
        id              : "ticket.tags",
        label           : "Tag",
        description     : "Any tag currently attached to the ticket.",
        type            : "string",
        appliesTo       : [],                                        // empty = universal across triggers
        // Optional: render a picker instead of a free-text input.
        // Use `options` for a static list, or `optionsProvider` for
        // a value set that needs to be resolved live.
        options         : [ { value : "vip", label : "VIP" }, { value : "billing", label : "Billing" } ],
        optionsProvider : "TagService@addon-tags.listTagOptions"
    }
];
```

`appliesTo` scopes the field to specific triggers. Empty or absent means universal.

For known value sets, declare `options` directly (array of strings, or array of `{ value, label }` structs). For lists that change at runtime (workflow statuses, organization roster, agent roster), declare an `optionsProvider` reference of the form `"Mapping@module.methodName"`; the rule editor resolves the call and uses its return value as the option list.

Boolean fields use the canonical pair:

```boxlang
options : [
    { value : "true",  label : "Yes" },
    { value : "false", label : "No"  }
]
```

because `AutomationService.readField` compares value strings, not native booleans.

### Declaring an action

```boxlang
settings.tesserabx.automationActions = [
    {
        id              : "slack.postToChannel",
        label           : "Post to Slack channel",
        description     : "Notify a Slack channel when the rule fires.",
        executor        : "SlackPostExecutor@example-slack",
        parameterSchema : [
            { name : "channel", label : "Channel", type : "string",   required : true, placeholder : "##incidents" },
            { name : "message", label : "Message", type : "textarea", required : true }
        ]
    }
];
```

The executor reads its parameters from `arguments.action.params.<name>`:

```boxlang
public struct function execute( required struct action, required any ticket, required any rule ){
    var params = arguments.action.params ?: {};
    // params.channel, params.message ...
    return { type : arguments.action.type, channel : params.channel ?: "" };
}
```

`AutomationService` normalizes the action struct into `{ type, params : { ... } }` before calling the executor, then routes the call through `ActionRegistry.dispatch( action, ticket, rule )`. The executor's return value lands in the rule-fires log.

### Parameter schema

Each action declares its own parameter schema as a list of field descriptors:

| Field             | Notes                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| `name`            | The key the form submits (becomes a key under `params` on disk).                                     |
| `label`           | Human label for the rule editor.                                                                     |
| `type`            | `"string"` \| `"select"` \| `"boolean"` \| `"textarea"` \| `"number"`                                |
| `required`        | Defaults to false.                                                                                   |
| `options`         | Array of strings or `{ value, label }` structs (for `type=select`).                                  |
| `optionsProvider` | `"Mapping@module.methodName"` for dynamic option lists; the editor resolves the call at render time. |
| `allowEmpty`      | Boolean; prepend a blank option labelled `emptyLabel`.                                               |
| `emptyLabel`      | Label for the blank option (`"Unassigned"`, `"--"`).                                                 |
| `placeholder`     | Optional placeholder text.                                                                           |
| `description`     | Optional help text.                                                                                  |

The same `options` / `optionsProvider` mechanism is supported on condition fields (see above).

### Storage shape

Rules persist actions in the new shape:

```json
[ { "type" : "setPriority", "params" : { "value" : "high" } } ]
```

Multi-field schemas land naturally as multi-key `params` structs. Existing rows stored in the legacy `{ type, value }` shape are normalized at read time by `AutomationService.normalizeAction`; no migration is required.

### Migration impact

Existing rules continue to evaluate identically. `ActionRegistry.dispatch` resolves the executor by id and calls it with the normalized `{ type, params }` struct; the four core executors (`SetPriorityExecutor`, `SetStatusExecutor`, `AssignToAgentExecutor`, `AssignByStrategyExecutor`) read `params.value` and wrap the same logic that previously lived in `AutomationService.applyOne`.

`AutomationService.listSupportedTriggers / listSupportedOps / listSupportedActions` now return registry-backed arrays, so add-on contributions automatically appear in any UI that listed the previous hard-coded constants.

---

