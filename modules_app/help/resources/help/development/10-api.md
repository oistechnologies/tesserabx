## API resources

The `api` module exposes the REST surface under `/api`. Add-ons can contribute their own endpoints either by mounting them under `/api/v1/<addon>/...` from the add-on's own router or by inlining handlers in the add-on module. Either way, the **`ApiResourceRegistry@api`** is the machine-readable catalog of every endpoint the application exposes. It does NOT emit routes; it lets cbswagger, the admin diagnostics surface, and any third-party tool list what exists.

Core seeds the registry with every route in `modules_app/api/config/Router.bx` (the eight `/v1/...` endpoints plus `/swagger`). Add-ons add to it through the manifest.

### Declaring an API resource

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.apiResources = [
    {
        id      : "exampleJira.get.status",
        method  : "GET",
        path    : "/api/v1/example-jira/status",
        version : "v1",
        handler : "JiraStatus",
        action  : "show",
        summary : "Current Jira sync status.",
        requiresAuth       : true,
        requiredPermission : "exampleJira.view"
    }
];
```

Each entry declares:

| Field                 | Required    | Notes                                                                              |
| --------------------- | ----------- | ---------------------------------------------------------------------------------- |
| `id`                  | yes         | Stable identifier. Conventionally `<module>.<verb>.<short>`.                       |
| `method`              | yes         | `GET`, `POST`, `PUT`, `PATCH`, or `DELETE`.                                        |
| `path`                | yes         | Full path, starting with `/api`. The registry does NOT auto-prefix.                |
| `version`             | yes         | Slug like `v1`. Used to group entries in diagnostics.                              |
| `handler`             | yes         | ColdBox handler reference, relative to the contributing module.                    |
| `action`              | yes         | Handler action method name.                                                        |
| `summary`             | recommended | One-line human description; appears in admin diagnostics.                          |
| `requiresAuth`        | recommended | Boolean. Default `true`. Set `false` only for public endpoints (login, docs).      |
| `requiredPermission`  | recommended | Permission id from `PermissionRegistry`. Empty means any authenticated agent.      |
| `mementifierIncludes` | optional    | Array of mementifier include names this route emits, for documentation.            |

### How routes are actually registered

The registry catalogs metadata; ColdBox still owns the routing. Add-ons register routes the standard way:

```
// in your add-on's ModuleConfig.bx
variables.routes = [
    { pattern : "/v1/example-jira/status", target : "JiraStatus.show", verbs : "GET" }
];
```

Or, for the api module specifically, you can mount your routes under `/api/v1/<addon>/...` by declaring them in your add-on's own router and accepting that the api module's entryPoint of `api` does NOT auto-prefix add-on routes; you must include `/api/...` in the pattern yourself, or attach your handlers as part of a separate module with its own entryPoint.

The recommended pattern for add-on REST endpoints is to mount them under a dedicated entryPoint (e.g. `example-jira-api`) and add the corresponding paths to the registry with their fully-qualified `/api/v1/...` value, accepting that you are documenting the contract independently of the routing.

### OpenAPI (cbswagger)

cbswagger is configured in `config/Coldbox.bx` to scan for routes under the `api/v1` prefix. Any add-on handler whose route resolves under that prefix will be picked up automatically, provided the handler carries the documented annotation style.

**BoxLang docblock gotcha.** Hyphenated annotation keys (e.g. `@request-body`) are dropped from function metadata. Use plural OpenAPI-shaped keys with inline JSON values:

```
/**
 * Show the current Jira sync status.
 *
 * @tags ["Jira"]
 * @summary Current Jira sync status
 * @responses { "200": { "description": "OK", "content": { "application/json": {} } } }
 */
function show( event, rc, prc ){ ... }
```

See [`feedback_boxlang_docblock_hyphens.md`](../.claude/projects/-Users-mrigsby-Data-BoxLang-Dev-TesseraBX-GIT-tesserabx/memory/feedback_boxlang_docblock_hyphens.md) for the full set of supported keys.

### Public extension contract

```
var registry  = wirebox.getInstance( "ApiResourceRegistry@api" );
var all       = registry.listAll();
var v1        = registry.listForVersion( "v1" );
var byModule  = registry.listByModule( "tickets" );
var single    = registry.findById( "api.tickets.show" );
```

## Webhook events

The `webhook_subscriptions` table lets an operator point an outbound URL at a list of event keys. Phase 8 replaces the hard-coded event catalog with **`WebhookEventRegistry@api`** so add-ons can publish their own events without editing core.

### Declaring a webhook event

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.webhookEvents = [
    {
        key         : "exampleJira.issue_linked",
        label       : "Jira issue linked to ticket",
        description : "Fires when an agent links a ticket to a Jira issue."
    }
];
```

Each entry declares:

| Field         | Required    | Notes                                                                |
| ------------- | ----------- | -------------------------------------------------------------------- |
| `key`         | yes         | Stable identifier. Conventionally `<module-or-addon>.<noun>_<verb>`. |
| `label`       | yes         | Human label rendered in the admin multi-select.                      |
| `description` | recommended | One-line explanation surfaced in the admin UI.                       |

The `"*"` wildcard subscription is handled at dispatch time and is NOT a registry entry; the registry catalogs concrete events only.

### Firing your event

Once registered, fire the event from your service layer:

```
wirebox.getInstance( "WebhooksService@api" ).dispatchForEvent(
    eventKey : "exampleJira.issue_linked",
    payload  : {
        ticket : { id : ticket.getId(), ticket_number : ticket.getTicketNumber() },
        jira   : { issue_key : issueKey, project : project }
    }
);
```

`WebhooksService` looks up every active subscription whose `event_keys` list includes the key (or `*`), signs the payload with the subscription's secret, POSTs it, and records the outcome in `webhook_deliveries`.

### Validation behavior

When an admin creates or updates a subscription, every event key in the comma-separated list is validated against the registry. `*` is always accepted; any other key must have been declared in core's seed or in a contributing add-on's manifest. Unknown keys raise `WebhooksService.UnknownEventKey`.

### Public extension contract

```
var registry = wirebox.getInstance( "WebhookEventRegistry@api" );
var catalog  = registry.listAll();
var keys     = registry.listKeys();
var ok       = registry.isRegistered( "ticket.created" );
```

For back-compat, `WebhooksService.eventCatalog()` still returns the previous `[ { key, label } ]` shape, sourced from the registry.

---

