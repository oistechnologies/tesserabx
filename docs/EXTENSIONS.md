# TesseraBX Extensions Guide

TesseraBX is extensible by third-party BoxLang ColdBox modules. A developer can ship an "add-on" as a standard ColdBox module, install it into a running TesseraBX deployment, and contribute navigation items, admin pages, ticket panels, dashboard widgets, channel adapters, automation actions, AI features, API routes, roles, custom field types, notification templates, and help pages, all without modifying core code.

This guide is the contract that add-on authors code against and the operator's reference for managing add-ons in a TesseraBX install. The companion [`docs/EXTENSIBILITY-PLAN.md`](EXTENSIBILITY-PLAN.md) is the phased plan for landing this contract; this file documents whatever portion of the contract has shipped.

> Status: Phase 1 (foundation) only. Discovery, manifest, version-range checking, enablement resolution, and the scaffolder are documented below. Later sections (registries, service interfaces, events, help pages) land as their respective phases complete.

---

## What an add-on is

An add-on is a **standard ColdBox 8+ module** that lives in one of TesseraBX's standard module locations:

- `modules_app/` for first-party add-ons that ship with TesseraBX itself
- `modules/` for third-party add-ons installed through CommandBox (`box install <slug>`)

ColdBox discovers both locations automatically. No custom loader, no special path. If your module loads in a stock ColdBox app, it loads in TesseraBX too.

What makes a ColdBox module a TesseraBX add-on is one extra block of settings inside its `ModuleConfig.bx`:

```boxlang
class {

    function configure(){
        settings = {
            tesserabx : {
                addonId         : "example-jira",
                displayName     : "Jira Sync",
                version         : "1.0.0",
                minCoreVersion  : "0.0.1",
                maxCoreVersion  : "",
                contributesTo   : [ "navigation", "ticketPanel", "automationAction" ],
                requiresAi      : false
            }
        };
        // ...rest of the module's normal configure() body
    }
}
```

A module without a `settings.tesserabx` block is a normal ColdBox module. TesseraBX does not surface it in the admin UI and does not track its enablement.

---

## Manifest fields

| Field            | Required | Notes                                                                                          |
| ---------------- | -------- | ---------------------------------------------------------------------------------------------- |
| `addonId`        | yes      | Stable slug. Becomes the primary key in the `addons` table. Use kebab-case.                    |
| `displayName`    | yes      | Human-readable label shown in the admin Add-ons page.                                          |
| `version`        | yes      | Your add-on's own version. Used for display only; TesseraBX does not compare add-on versions. |
| `minCoreVersion` | yes      | Minimum TesseraBX core version your add-on supports. Add-on is rejected if core is older.      |
| `maxCoreVersion` | no       | Inclusive maximum. **Blank, missing, or omitted means "any version >= minCoreVersion"**.        |
| `contributesTo`  | no       | Array of contribution kinds for documentation purposes. No runtime enforcement.                |
| `requiresAi`     | no       | Defaults to false. When true, every UI surface this add-on contributes is hidden when `AI_ENABLED=false` (enforced once Phase 4's UI registries land).  |

### Version-range semantics

`minCoreVersion` is required. `maxCoreVersion` is optional with intentional "open upper bound" semantics:

- When `maxCoreVersion` is blank, missing, or the key is omitted entirely, the add-on is accepted on **any core version equal to or greater than `minCoreVersion`**. An add-on author can opt into "works forever forward" without having to bump the manifest on every TesseraBX release.
- When `maxCoreVersion` is present, it caps the supported range inclusively.

Versions are compared in semantic-version style ("1.10.0" > "1.2.0"). Pre-release suffixes after a dash are ignored.

If the running TesseraBX version falls outside an add-on's declared range, the add-on is still recorded in the `addons` table but marked `compatible = false` with a `compatibility_message`. The admin UI will surface the incompatibility, and `AddonRegistryService.isEnabled()` returns false for the add-on at every tenant.

The running TesseraBX version is read from the `appVersion` setting in `config/Coldbox.bx`. Bump that and the matching value in `box.json` together on every release.

---

## Discovery

At app boot, the `AddonDiscoveryInterceptor` listens on ColdBox's `afterAspectsLoad` event. Once every module has been loaded, the interceptor calls `AddonRegistryService.syncFromLoadedModules()`, which:

1. Walks `controller.getSetting( "modules" )` to find every loaded ColdBox module.
2. Skips modules without a `settings.tesserabx` block.
3. Validates each manifest has the required fields. A missing required field is logged and the module is skipped.
4. Compares each manifest's `minCoreVersion` and `maxCoreVersion` against the running `appVersion`.
5. Upserts a row into `addons`, preserving any existing `enabled` and `enablement_mode` choices an admin previously made.

The sync runs on every app boot, so reinstalling, reinit'ing, or restarting picks up new manifests and notices changes to existing ones.

A row in `addons` represents a **discovered** add-on, not necessarily an **enabled** one. See enablement below.

---

## Enablement resolution

Add-ons can be globally enabled or disabled, and within that, can be set to apply to every organization or only to a chosen subset.

The data model:

- `addons.enabled` (boolean): the global on/off switch for the add-on. Defaults true when first discovered.
- `addons.enablement_mode` (string, `'all'` or `'specific'`): when the add-on is globally enabled, this picks the resolution rule.
- `addon_organization_enablement` (table): per-organization rows used only when `enablement_mode = 'specific'`.

Call `AddonRegistryService.isEnabled( addonId, organizationId )` from any code that needs to know whether to honor an add-on's contribution at a specific tenant. The resolution rule is:

```
addons.enabled = false                           ⇒ false   (off everywhere)
add-on marked incompatible at discovery          ⇒ false   (off everywhere)
enablement_mode = 'all'                          ⇒ true    (on for every organization)
enablement_mode = 'specific' AND row exists      ⇒ that row's enabled value
enablement_mode = 'specific' AND no row exists   ⇒ false   (default off in specific mode)
```

A deployment that does not want per-tenant granularity simply leaves every add-on in `enablement_mode = 'all'`. The admin UI lands in Phase 4; until then, switching modes or setting per-org rows is done through `AddonRegistryService.setEnablementMode()` and `setOrgEnablement()` or direct SQL.

---

## Scaffolding a new add-on

A CommandBox task generates a skeleton TesseraBX add-on under `modules/<slug>/` with the manifest block pre-filled, the standard folder layout, a placeholder install spec, and a README:

```bash
box task run tasks/ScaffoldAddon.bx <addon-slug> [displayName="Friendly Name"]
```

The generated module is a valid ColdBox module that loads cleanly and registers in the `addons` table on the next reinit. Open `modules/<slug>/ModuleConfig.bx`, edit the manifest details, then start adding handlers, services, and (as registries land in later phases) contributions to those registries.

---

## Service contracts

Each core module that exposes a public service for add-ons ships a contract class under `models/contracts/`. The contract class is a regular BoxLang class (BoxLang has no `interface` keyword) whose method bodies throw, with documentation describing the live service's public surface. **Do not instantiate the contract class.** Add-ons resolve the live implementation through WireBox:

```boxlang
property name="tickets" inject="TicketsService@tickets";
// or
var svc = wirebox.getInstance( "TicketsService@tickets" );
```

The contract files are the stable surface for add-on consumption. The contract describes only the methods add-ons are expected to need; methods absent from the contract (internal helpers, scheduler-only routines) may change without notice.

Available contracts in Phase 2:

| Contract file                                                                 | Live service                       |
| ----------------------------------------------------------------------------- | ---------------------------------- |
| `modules_app/tickets/models/contracts/ITicketsService.bx`                     | `TicketsService@tickets`           |
| `modules_app/contacts/models/contracts/IContactsService.bx`                   | `ContactsService@contacts`         |
| `modules_app/audit/models/contracts/IAuditService.bx`                         | `AuditService@audit`               |
| `modules_app/notifications/models/contracts/INotificationsService.bx`         | `NotificationsService@notifications` |
| `modules_app/ai/models/contracts/IAiMiddleware.bx`                            | `AiMiddleware@ai`, `AiCapability@ai` |

---

## DTOs

Each module also ships DTO mapper services under `models/dtos/` that convert Quick entities into stable struct shapes for cross-boundary travel. Use these when an add-on needs to serialize a core entity, hand it to a webhook, or otherwise expose its data outside the originating module.

```boxlang
var dto = wirebox.getInstance( "TicketDto@tickets" );
var record = dto.fromTicket( ticketEntity );
// record is a struct with stable snake_case keys; JSON-serializable.
```

Available DTO mappers in Phase 2:

| DTO mapper                                  | Methods                                                   |
| ------------------------------------------- | --------------------------------------------------------- |
| `TicketDto@tickets`                         | `fromTicket`, `fromTicketMessage`, `fromAttachment`, `fromTicketArray` |
| `ContactDto@contacts`                       | `fromContact`, `fromOrganization`, `fromOffice`, `fromContactArray`, `fromOrganizationArray` |
| `AuditEventDto@audit`                       | `fromAuditEvent`, `fromAuditEventArray`                   |
| `NotificationDto@notifications`             | `fromNotification`, `fromNotificationArray`               |

DTO keys are snake_case to match the JSON the API already returns. Sensitive fields (password hashes, MFA secrets, recovery codes) are excluded from DTOs by design.

---

## Tenant scope

`Organization` is the tenant boundary. Every tenant-scoped table carries an `organization_id` column from its first migration; client-side queries are filtered automatically through a Quick global scope; agent-side queries see across organizations.

### Building a tenant-scoped add-on entity

Two steps. First, extend the shared base entity:

```boxlang
class extends="tesserabx.modules.contacts.models.TesseraBXEntity" {
    variables._mapping = "MyAddonThing@my-addon";

    this.table = "my_addon_things";

    property name="id";
    property name="organizationId" column="organization_id";
    // ...your columns
}
```

Second, apply the tenant scope in `applyGlobalScopes`:

```boxlang
function applyGlobalScopes( builder ){
    getInstance( "TenantScope@contacts" ).apply( arguments.builder );
    return this;
}
```

Your entity now participates in the same client-side vs agent-side visibility rules as core entities. Client-side surfaces (`/`, the embedded widget) see only the requesting Contact's organization; agent-side surfaces (`/agent`, including admin) see everything.

### The tenancy guard

For hand-written `qb` queries that the entity-scope mechanism cannot help with, the `TenancyGuard@contacts` service is the imperative cousin of the global scope:

```boxlang
var q = newQuery().from( "my_addon_things" );
wirebox.getInstance( "TenancyGuard@contacts" )
       .applyScope( q, organizationId );
// or, if you added the predicate manually:
wirebox.getInstance( "TenancyGuard@contacts" )
       .assertHasOrgPredicate( q );
```

`applyScope` is the safer choice: it adds the predicate for you. `assertHasOrgPredicate` is a runtime safety net for code that adds the predicate manually upstream; it throws `TenancyGuard.MissingOrgPredicate` when the structured wheres array does not contain an `organization_id` predicate. Raw SQL fragments cannot be inspected; if you must use `whereRaw`, pass `acceptRaw=true` to `assertHasOrgPredicate` after hand-verifying the fragment.

### Tenancy rules

- Every add-on table that holds per-tenant data MUST carry `organization_id` in its **first** migration. Retrofitting tenancy is forbidden.
- Add-ons MUST NOT bypass `TenantScope` from client-side surfaces. Calls like `entity.withoutGlobalScopes()` are reserved for agent-side code that has a legitimate cross-tenant reason (reporting, admin).
- Tickets without a `Contact` (accountless tickets from unregistered senders) have `organization_id IS NULL`. They are visible to provider agents only and never to any client user.

---

## Add-on migrations

`cfmigrations` is configured as a single-directory runner (see `.cfmigrations.json`). Add-ons ship their migrations into the same global directory as core: `resources/database/migrations/`.

To avoid name collisions across add-ons and core:

1. Prefix every migration filename with your `addonId`. Example: `exampleJira_2026_06_01_000010_create_jira_links.cfc`.
2. Use the same timestamped sortable format core uses (`YYYY_MM_DD_HHmmss`). The slug prefix sorts before the timestamp, so all of your add-on's migrations run as a block in declared order.
3. Use the same component declaration core uses: `component { function up( schema, qb ){...}; function down( schema, qb ){...}; }`.
4. Every per-tenant table MUST include an `organization_id` column with a FK and CASCADE on delete, and the entity that fronts the table MUST apply `TenantScope@contacts`. Migrations that introduce a per-tenant table without `organization_id` are wrong and will fail the tenancy review in later phases.

A future phase may extend the migration runner to discover per-module migration folders automatically; until then, the slug-prefix convention is the supported approach.

---

## Per-tenant settings

Each add-on can declare a settings schema in its `ModuleConfig.bx` manifest:

```boxlang
settings = {
    tesserabx : {
        addonId        : "example-jira",
        // ... other manifest fields
        settings       : [
            {
                key         : "jira.baseUrl",
                type        : "string",
                label       : "Jira Base URL",
                description : "Your Jira instance URL (no trailing slash).",
                default     : "",
                secret      : false,
                perTenant   : true
            },
            {
                key         : "jira.apiToken",
                type        : "string",
                label       : "API token",
                description : "Service account token with read+write permissions.",
                default     : "",
                secret      : true,
                perTenant   : true
            }
        ]
    }
};
```

The declared `default` is the global value. Per-tenant overrides live in the `addon_settings` table. Resolution rule:

1. If an override exists in `addon_settings` for `(addon_id, organization_id, setting_key)`, return it.
2. Otherwise return the manifest-declared `default`.
3. If neither exists, return null.

Read and write through `SettingsRegistry@core`:

```boxlang
var settings = wirebox.getInstance( "SettingsRegistry@core" );

// Read
var url = settings.resolve( "example-jira", "jira.baseUrl", organizationId );

// Write
settings.set( "example-jira", "jira.baseUrl", "https://jira.example.com", organizationId, currentAgentId );

// Clear (fall back to manifest default)
settings.clear( "example-jira", "jira.baseUrl", organizationId );

// List all overrides for a tenant's add-on
var overrides = settings.listOverridesForOrganization( "example-jira", organizationId );

// List all declared settings for an add-on
var descriptors = settings.listDescriptors( "example-jira" );
```

Direct INSERTs into `addon_settings` bypass the perTenant=false guard and the unknown-key check; always go through `SettingsRegistry.set()`.

The admin UI that drives these (Phase 4) renders a generic form from `listDescriptors()` per add-on, grouped under "Add-on Settings".

---

## Events

Every state transition core cares about announces an interceptor event other modules and add-ons can listen on. Add-ons hook into these events by declaring an interceptor in their `ModuleConfig.bx` with a method named after the event, then doing whatever work the add-on needs.

```boxlang
// modules/example-jira/interceptors/JiraSyncInterceptor.bx
class {
    property name="wirebox" inject="wirebox";

    function configure(){}

    function onTicketStatusChanged( event, interceptData, rc, prc ){
        // interceptData carries the payload struct emitted by the
        // event source. See the canonical payload shape below.
    }
}
```

Then register the interceptor in `ModuleConfig.bx`:

```boxlang
variables.interceptors = [
    {
        class      : "#moduleMapping#.interceptors.JiraSyncInterceptor",
        name       : "JiraSyncInterceptor",
        properties : {}
    }
];
```

### Canonical event payload

Every event TesseraBX announces from Phase 3 onwards uses the same envelope (produced by `EventPayloadBuilder@core`):

```
{
    event          : "onContactCreated",
    occurredAt     : "<ISO-8601 UTC>",
    organizationId : "<uuid>" or "",
    actorType      : "agent" | "contact" | "system",
    actorId        : "<uuid>" or "system",
    entity         : { type: "Contact", id: "<uuid>" },
    before         : <struct or null>,
    after          : <struct or null>,
    metadata       : <struct>
}
```

The five pre-Phase-3 events keep their original payload shapes for backwards compatibility with the existing core interceptors that consume them:

- `onTicketCreated`: `{ ticket : <Ticket entity>, accountless : boolean }`
- `onTicketMessageAdded`: `{ message : <TicketMessage entity>, ticket : <Ticket entity> }`
- `onTicketStatusChanged`: `{ ticket : <Ticket entity>, statusChange : { from : "...", to : "..." } }`
- `onKbArticlePublished`: `{ article : <Article entity> }`

New listeners for these events get the existing entity-shaped struct, not the canonical envelope.

### Async vs sync policy

By default, **new events use `announceAsync`**: they cannot stall the request that triggered them. Add-on listeners therefore run after the originating response is committed, in a separate thread.

A handful of events stay **synchronous** because they need to influence the in-flight transaction (automation rules that mutate the same ticket the user just edited, AI triage that writes summary fields before the response renders). The five pre-Phase-3 events are sync for this reason.

When listening on an async event, do not assume the originating database row is still in its post-write state. Read the entity by id if you need the latest values.

### Event catalog (Phase 3)

Events fire from these core modules. The list grows as later phases (channels, SLA, automation, KB-beyond-publish, AI, API webhooks) ship their own events.

**tickets** (declared in `modules_app/tickets/ModuleConfig.bx`):

| Event | Sync? | Fires when |
| --- | --- | --- |
| `onTicketCreated` | sync | A ticket is created (with or without a Contact). |
| `onTicketMessageAdded` | sync | A reply or internal note is added. |
| `onTicketStatusChanged` | sync | A status transition occurs. |
| `onTicketAssigned` | async | Assignment changes (including unassignment). |
| `onTicketTagsAdded` | async | One or more tags are added. |
| `onTicketAttachmentAdded` | async | A file is attached. |
| `onTicketAttachmentDeleted` | async | An attachment is soft-deleted. |
| `onTicketPromotedToContact` | async | An accountless ticket's sender is promoted to a real Contact. |

**contacts** (declared in `modules_app/contacts/ModuleConfig.bx`):

| Event | Sync? | Fires when |
| --- | --- | --- |
| `onOrganizationCreated` | async | A new organization is created. |
| `onContactProvisioned` | async | A new Contact account is provisioned. |
| `onContactDeactivated` | async | A Contact is deactivated. |
| `onContactRoleGranted` | async | A role is assigned to a Contact. |
| `onContactRoleRevoked` | async | A role is revoked from a Contact. |
| `onOrganizationDomainMapped` | async | A domain is mapped to an organization. |
| `onContactMerged` | async | Two Contacts are merged. |

**agent + RBAC** (declared in `modules_app/agent/ModuleConfig.bx`):

| Event | Sync? | Fires when |
| --- | --- | --- |
| `onAgentCreated` | async | A new agent account is created. |
| `onAgentUpdated` | async | An agent profile is updated (and `isActive` did NOT flip). |
| `onAgentActivated` | async | An agent is activated (isActive flips false → true). |
| `onAgentDeactivated` | async | An agent is deactivated (isActive flips true → false). |
| `onAgentRoleGranted` | async | A role is granted to an agent. |
| `onAgentRoleRevoked` | async | A role is revoked from an agent. |

**knowledgebase**: only `onKbArticlePublished` (sync) ships in Phase 3. Other lifecycle events for articles are planned for a later phase.

---

## Audit-event contributions

Add-ons can write to the central audit log alongside core. Use `AuditService@audit`:

```boxlang
property name="auditService" inject="AuditService@audit";

auditService.record(
    eventType      : "exampleJira.issueCreated",
    entityType     : "Ticket",
    entityId       : ticketId,
    organizationId : orgId,
    actorType      : "agent",
    actorId        : currentAgentId,
    metadata       : { jiraIssueKey : "PROJ-123", projectKey : "PROJ" },
    source         : "example-jira"
);
```

The `source` argument is the add-on's `addonId`. Core events leave it null. The admin audit search UI exposes a Source filter dropdown so an operator can see exactly what each add-on has done, independently of core noise.

### Declaring your audit event types in the manifest

So that an add-on's event types appear in the admin search dropdown **before** they have ever fired, declare them in the manifest:

```boxlang
settings = {
    tesserabx : {
        addonId : "example-jira",
        // ... other manifest fields
        auditEvents : [
            { type : "exampleJira.issueCreated", label : "Jira issue created", severity : "info" },
            { type : "exampleJira.issueClosed",  label : "Jira issue closed",  severity : "info" }
        ]
    }
};
```

`AuditService.listEventTypes()` merges the distinct types already in the log with every add-on's declared types, deduplicates, and returns a sorted array. The dropdown surfaces a type the moment the add-on is discovered, not the first time an event of that type happens.

### Audit-event naming convention

Use dotted notation with the add-on slug as the prefix: `<addonId>.<verb_noun>`. Examples: `example-jira.issue_created`, `example-jira.issue_closed`, `billing.invoice_sent`. Core uses the same convention with an entity prefix (`ticket.created`, `contact.merged`, etc.).

---

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

## What is not yet documented here

Later phases of the extensibility plan add sections to this file as they land:
- **Phase 5**: channel adapter contract.
- **Phase 6**: automation triggers, conditions, and actions.
- **Phase 7**: AI feature, provider, and embedding consumer registries.
- **Phase 8**: API resource registry, OpenAPI contribution, and webhook event registry.
- **Phase 9**: custom fields generalization and the entity-extension table convention.
- **Phase 10**: notification template registry and delivery channel plug-ins.
- **Phase 11**: help page and section registries (this guide will then also be rendered as an in-app help section).
- **Phase 12**: reference sample add-on and Quick start.

See [`docs/EXTENSIBILITY-PLAN.md`](EXTENSIBILITY-PLAN.md) for the full plan.
