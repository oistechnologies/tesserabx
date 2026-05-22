## Roles and permissions

TesseraBX layers a permission model on top of the existing role-keyed RBAC. Add-ons declare both in their manifest:

```boxlang
settings = {
    tesserabx : {
        addonId : "example-jira",
        permissions : [
            { id : "exampleJira.view",   label : "View Jira integration data" },
            { id : "exampleJira.manage", label : "Manage Jira connection settings" }
        ],
        roles : [
            {
                id          : "jira-viewer",
                label       : "Jira Viewer",
                description : "Read-only access to the Jira integration.",
                surface     : "agent",
                permissions : [ "exampleJira.view" ]
            }
        ]
    }
};
```

Roles are declared with `surface = "agent"` (provider-side) or `"contact"` (client-side). Permissions are free-form ids; the agent admin Users page renders the role picker for whichever surface is being edited. cbSecurity rules continue to use role keys directly for backwards compatibility; the registries are additive.

Lookup at runtime:

```boxlang
property name="roles"       inject="RoleRegistry@agent";
property name="permissions" inject="PermissionRegistry@agent";

var roleStruct = roles.findById( "jira-viewer" );      // null if not registered
var allPerms   = permissions.listAll();
var holds      = arrayContains( viewer.permissions, "exampleJira.view" );
```

Within a request, the application helper `tbxViewer()` resolves the current viewer's roles into permission ids, so every UI registry (navigation, admin pages, ticket panels, dashboard widgets) can gate on a `requiredPermission` field.

---

## Navigation

Six navigation zones exist:

| Surface | Menu | Where |
| --- | --- | --- |
| `portal` | `main`    | left-hand sidebar on `/` |
| `portal` | `account` | account dropdown on `/` |
| `portal` | `topbar`  | top bar on `/` (sparse today) |
| `agent`  | `main`    | left-hand sidebar on `/agent` |
| `agent`  | `account` | account dropdown on `/agent` |
| `agent`  | `topbar`  | top bar on `/agent` (sparse today; the notification bell stays inline) |

Add-ons contribute entries via manifest:

```boxlang
settings.tesserabx.navigation = [
    {
        id                 : "exampleJira.main",
        surface            : "agent",
        menu               : "main",
        label              : "Jira",
        route              : "/agent/example-jira",
        icon               : "bi bi-link-45deg",
        sortWeight         : 70,
        requiresAuth       : true,
        requiredPermission : "exampleJira.view"
    }
];
```

Resolution order: filter by `(surface, menu)`, apply overrides from `registry_overrides` (registry `'navigation'`), filter by viewer (`requiresAuth`, `requiresAnonymous`, `capabilityFlag`, `requiredPermission`), sort by `sortWeight`. Sparse `requiredPermission` allows public/login-flow entries (the portal "Sign in" link uses `requiresAnonymous : true`).

The layout helper `#tbxNavigation( surface, menu )#` returns the visible entries for the current viewer; iterate it in the layout to emit each menu zone.

---

## Admin pages

The 14 cards on the `/agent/admin` landing page are now registry-driven. Each card has an id, title, description, route, icon, sort weight, and required permission. Add-ons contribute:

```boxlang
settings.tesserabx.adminPages = [
    {
        id                 : "exampleJira.connection",
        title              : "Jira connection",
        description        : "Configure the Jira instance and credentials.",
        route              : "/agent/admin/example-jira",
        icon               : "bi bi-link-45deg",
        sortWeight         : 800,
        requiredPermission : "exampleJira.manage"
    }
];
```

The Phase 4 build added two new admin pages that drive earlier-phase services: `/agent/admin/addons` (list every discovered add-on with global enable, enablement-mode, and per-organization rows) and `/agent/admin/addon-settings` (admin UI placeholder for the SettingsRegistry from Phase 2; the full form is a Phase 11 follow-up). Both require the `admin.addons.manage` permission.

---

## Ticket detail panels

Add-ons can render a card on the right column or a tab on the agent ticket-detail page. Declare:

```boxlang
settings.tesserabx.ticketPanels = [
    {
        id                 : "exampleJira.linkedIssue",
        position           : "right",          // or "tab"
        label              : "Linked Jira issue",
        partial            : "panels/jira-linked-issue",
        module             : "example-jira",
        sortWeight         : 500,
        requiredPermission : "exampleJira.view",
        defaultCollapsed   : true
    }
];
```

The partial renders via `#view( view = partial, module = module, args = { ticket : prc.ticket } )#` inside the show.bxm loop. The host passes the current `prc.ticket` entity through `args`.

Note for Phase 4: core's existing ticket-show panels (AI Summary, SLA, Assignment, etc.) remain rendered inline in `modules_app/agent/views/tickets/show.bxm` and are NOT yet migrated to the registry. Add-on panels render after the inline core panels. A future phase may extract core panels into the registry too; until then, the registry is purely an add-on contribution surface.

---

## Dashboard widgets

Same shape for the `/agent/reports` dashboard:

```boxlang
settings.tesserabx.dashboardWidgets = [
    {
        id                 : "exampleJira.syncStatus",
        title              : "Jira sync status",
        partial            : "widgets/jira-sync-status",
        module             : "example-jira",
        dataProvider       : "JiraReportingService@example-jira",   // optional
        dataMethod         : "syncStatusForDashboard",              // optional
        defaultGridSize    : "col-12 col-md-6",
        sortWeight         : 500,
        requiredPermission : "exampleJira.view"
    }
];
```

The host loops `#tbxDashboardWidgets()#`, invokes each widget's data provider (when declared), and renders the named partial wrapped in the declared grid size. The same deferral applies: core's existing six dashboard widgets (overview tiles, ticket-volume line chart, three doughnut charts, backlog table, agent-load table) remain rendered inline and are not yet migrated to the registry.

---

## Asset publishing

Add-ons that ship CSS or JavaScript declare:

```boxlang
settings.tesserabx.assets = [
    { kind : "css", surface : "agent", href : "/modules/example-jira/resources/css/jira.css", sortWeight : 500 },
    { kind : "js",  surface : "agent", src  : "/modules/example-jira/resources/js/jira.js",   sortWeight : 500, defer : true }
];
```

Both layouts emit `#tbxAssetCss( surface )#` inside `<head>` and `#tbxAssetJs( surface )#` just before `</body>`. The add-on is responsible for serving its own asset paths (typically via the static-file serving for `/modules/<slug>/resources/...`).

---

## Override table for UI registries

Admin overrides for the four UI registries land in a single generic table: `registry_overrides` with columns `(registry, entry_id, organization_id nullable, disabled, sort_weight_override, label_override, payload)`. An override row can:

- **Disable** an entry that would otherwise show up.
- **Reorder** by setting `sort_weight_override`.
- **Rename** by setting `label_override`.

Resolution per registry: the per-tenant row (matching `organization_id`) wins over the global row (`organization_id IS NULL`). The Add-ons admin page in Phase 4 lists every discovered add-on; finer-grained per-entry override controls are deferred to a follow-up.

---

