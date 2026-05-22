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

## Channel adapters

A channel adapter is an add-on contribution that lets tickets arrive from, and replies leave through, a transport core does not ship (Slack DM, SMS, Discord, an in-house webhook, etc.). The email transport ships as a core channel adapter so the registry is exercised by core itself.

### Implementing an adapter

Implement the method shape documented in `modules_app/channels/models/contracts/IChannelAdapter.bx`. Do NOT extend the contract class; just match its public surface. Every adapter must implement:

| Method                                          | Purpose                                                                                    |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `getChannelId()` → string                       | Stable identifier, lowercase, no spaces (e.g., `"email"`, `"slack-dm"`).                   |
| `getDisplayName()` → string                     | Human label for the admin Channels page.                                                   |
| `getIcon()` → string                            | Bootstrap-icon class for the admin list. May return `""`.                                  |
| `isPullBased()` → boolean                       | `true` if the host scheduler invokes `pollOnce()`; `false` for push (webhook) adapters.    |
| `verifyConfig( config )` → struct               | Admin Channels UI calls this when an operator wants to confirm a credential change.        |
| `pollOnce()` → numeric                          | Pull-based only: fetch any waiting messages and process them. Return the count handled.    |
| `normalizeInbound( raw )` → struct              | Convert one source-shaped payload into the host-normalized inbound struct (shape below).   |
| `sendOutbound( ticketMessage, ticket )` → struct | Dispatch a TicketMessage out through the channel. Returns `{ ok, error, channelMessageId }`. |

### Registering an adapter

Two paths:

**Manifest (the add-on path):**

```boxlang
// modules/my-addon/ModuleConfig.bx
settings.tesserabx.channelAdapters = [
    { mapping : "MyChannelAdapter@my-addon" }
];
```

Then map the implementation in `onLoad()` so WireBox can resolve it:

```boxlang
binder.map( "MyChannelAdapter@my-addon" )
      .to( "#moduleMapping#.models.MyChannelAdapter" )
      .asSingleton();
```

`ChannelAdapterRegistry@channels` walks every loaded module's manifest at boot, resolves each mapping, queries it for channel id / display name / icon, and caches the (id → mapping) lookup. After that, callers resolve adapters by channel id:

```boxlang
var registry = wirebox.getInstance( "ChannelAdapterRegistry@channels" );
var adapter  = registry.adapterFor( "my-channel" );
var result   = adapter.sendOutbound( ticketMessage, ticket );
```

**Imperative (the core path):**

Core's email channel adapter does NOT declare itself in a manifest because that would make `channels` appear as a distinct add-on in the admin Add-ons page. Instead, core registers imperatively in its `onLoad()`:

```boxlang
controller.getWireBox()
          .getInstance( "ChannelAdapterRegistry@channels" )
          .register( "EmailChannelAdapter@channels" );
```

Either path arrives at the same in-memory cache. Add-ons should prefer the manifest path so the admin UI surfaces the add-on as a self-contained installable artifact.

### Inbound normalized struct contract

`normalizeInbound( rawPayload )` MUST return a struct with every documented key populated. Fields whose source has no equivalent stay as empty strings, empty structs, or empty arrays. NEVER omit a key:

```
{
    messageId         : string,     // stable id from the source
    channelId         : string,     // the adapter's getChannelId()
    from              : string,     // sender display (free-form)
    senderEmail       : string,     // canonicalized email or ""
    senderHandle      : string,     // platform-specific id, or ""
    subject           : string,     // short title (may be derived from body)
    body              : string,     // plain-text body (HTML stripped)
    inReplyTo         : string,     // upstream id of the parent message, or ""
    references        : string,     // space-separated parent chain, or ""
    loopGuardHeaders  : struct,     // headers/markers identifying auto-responders
    attachments       : array,      // [{ path, originalFilename, contentType, sizeBytes }, ...]
    receivedAt        : datetime,   // when the source claimed the message arrived
    raw               : struct      // pass-through of the source payload for audit
}
```

Hand the normalized struct to `TicketsService` to create or append. The host loop-guard, blacklist check (`ChannelsService.isBlocked`), reply-matching, and duplicate detection happen between `normalizeInbound` and `TicketsService.createTicket` / `addMessage` in the existing core pipeline; new adapters can reuse that pipeline or implement their own pre-checks. Bypassing `ChannelsService.isBlocked` is not recommended.

### Polling cadence and outbound

Pull-based adapters do NOT manage their own timers. The host scheduler iterates the registry via `ChannelAdapterRegistry.pollAll()` and invokes each pull-based adapter's `pollOnce()` once per cycle.

Outbound dispatch is currently routed via the existing `OutboundEmailInterceptor` (which knows how to call `OutboundEmailService` for the email channel). Generalizing it into a generic `OutboundDispatchInterceptor` that resolves the right adapter by ticket source and calls `adapter.sendOutbound()` is a Phase 5 follow-up. Today, add-on adapters dispatch by registering their own listener on the relevant `onTicket*` events.

---

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

## AI features, providers, and embeddings

AI is strictly optional in TesseraBX. The `AI_ENABLED` env var gates every code path that would call an AI provider; when it is `"false"`, AiMiddleware short-circuits and feature handlers render their non-AI fallbacks. Phase 7 layers three add-on registries on top:

| Registry                              | Purpose                                                                              |
| ------------------------------------- | ------------------------------------------------------------------------------------ |
| `AiFeatureRegistry@ai`                | Declared AI features (the strings passed as the `feature` arg to AiMiddleware).      |
| `AiProviderRegistry@ai`               | Available provider backends (bx-ai today; add-ons can plug in Anthropic, Azure, etc.). |
| `EmbeddingConsumerRegistry@ai`        | Content sources that get embedded into pgvector for semantic search.                  |

### AI feature registry

Core ships seven features: `triage`, `suggested-reply`, `thread-summary`, `reply-tone`, `kb-draft`, `kb-index`, `kb-suggest`. Add-on contribution:

```boxlang
settings.tesserabx.aiFeatures = [
    {
        id                  : "billing.invoice-summary",
        label               : "Invoice summary",
        description         : "Generate a one-line summary of a billing invoice.",
        defaultSystemPrompt : "You write concise invoice summaries.",
        defaultModel        : "",
        kind                : "completion"
    }
];
```

`defaultSystemPrompt` is the prompt used when the `ai_system_prompts` table has no row for the feature; the admin Settings → AI prompts page (when built) writes overrides into that table that take precedence.

Feature entries always carry `requiresAi : true`. UI registry entries that contribute an AI surface (a ticket panel, a navigation item, a dashboard widget) should set their own `requiresAi : true`; the Phase 4 UI registries hide them when `AI_ENABLED=false`. The feature registry itself does NOT auto-hide; callers gate on `AiCapability.isFeatureEnabled(featureId)` before each invocation.

### AI provider registry

Core ships the `bx-ai` provider (wraps the `aiChat` / `aiEmbed` BIFs). Add-ons declare additional providers:

```boxlang
settings.tesserabx.aiProviders = [
    {
        id      : "anthropic-direct",
        label   : "Anthropic Claude (direct)",
        mapping : "AnthropicProvider@my-addon"
    }
];
```

The `mapping` resolves through WireBox to a class that implements the `IAiProvider` contract: `getProviderId`, `getDisplayName`, `verifyConfig`, `listModels`, `complete`, `embed`. See `modules_app/ai/models/contracts/IAiProvider.bx` for full signatures.

**Important caveat for Phase 7**: `AiMiddleware` currently calls `aiChat` and `aiEmbed` BIFs inline. The provider registry exists and `BxAiProvider` wraps both BIFs, but AiMiddleware is not yet refactored to resolve through the registry. Registering an add-on provider has NO runtime effect on the middleware today; it positions add-ons for a future middleware refactor.

### Embedding consumer registry

Core ships one consumer: `kb.article` (wraps the existing `KbIndexingService` flow that writes published-article vectors to `kb_articles.embedding`). Add-on consumers register additional content sources:

```boxlang
settings.tesserabx.embeddingConsumers = [
    {
        id          : "example.confluence-page",
        label       : "Confluence pages",
        description : "Indexes pages from the Confluence space the add-on syncs.",
        feature     : "example.confluence-index",
        mapping     : "ConfluenceEmbeddingConsumer@example-confluence",
        dimension   : 1536
    }
];
```

The consumer class implements the embedding pipeline for its content type:

- `getTextForEmbedding(entityId) → string`: assemble the text to embed.
- `saveEmbedding(entityId, vector) → void`: persist the vector to whatever table/column the consumer owns.
- `listEntitiesNeedingIndex() → array<id>`: return the entity ids that need (re)indexing on a scheduled sweep.

A scheduled task that iterates `EmbeddingConsumerRegistry.listAll()` and re-embeds stale entries across every consumer is a follow-up; today the only path that triggers embedding is the existing `onKbArticlePublished` interceptor for KB articles.

### The AI-off invariant

When `AI_ENABLED=false`:

1. `AiCapability.isEnabled()` returns false.
2. `AiCapability.isFeatureEnabled(<any feature id>)` returns false.
3. `AiMiddleware.complete(...)` returns `{ outcome : "disabled", ... }` without calling any provider.
4. `AiMiddleware.embed(...)` returns `{ outcome : "disabled", ... }` without calling any provider.
5. Every UI registry entry with `requiresAi : true` is filtered out by the registry's visibility check (Phase 4 contract).
6. Add-on AI features inherit this gating automatically because the AI feature registry sets `requiresAi : true` on every entry.

There is **no separate config flag for add-on AI features**: declaring an AI feature in the manifest is sufficient to inherit the gating, because every entry is `requiresAi : true` by construction.

---

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

## Custom fields

Custom fields ship with the `tickets` module but generalize across four core entity types as of Phase 9: **ticket**, **contact**, **organization**, and **article** (KB article). Definitions live in the shared `custom_field_definitions` table (one row per `entity_type`, `key`). Values live in entity-specific tables that share the same typed-column shape (`value_text`, `value_number`, `value_date`, `value_boolean`).

| Entity type    | Value table                          | FK column           |
| -------------- | ------------------------------------ | ------------------- |
| `ticket`       | `ticket_custom_field_values`         | `ticket_id`         |
| `contact`      | `contact_custom_field_values`        | `contact_id`        |
| `organization` | `organization_custom_field_values`   | `organization_id`   |
| `article`      | `kb_article_custom_field_values`     | `article_id`        |

### Service contract

`CustomFieldsService@tickets` is the single service all four entity types use. The schema methods take an `entityType` argument:

```
var svc = wirebox.getInstance( "CustomFieldsService@tickets" );
svc.createDefinition( entityType : "contact", key : "vip_code", label : "VIP code", fieldType : "text" );
svc.listDefinitions( entityType : "contact", activeOnly : true );
```

The value methods take both `entityType` and `entityId`:

```
svc.getValuesFor( entityType : "contact", entityId : contact.getId() );
svc.setValuesFor(
    entityType   : "contact",
    entityId     : contact.getId(),
    values       : { "<definitionId>" : "raw form value" },
    actorAgentId : currentAgentId()
);
```

`supportedEntities()` returns the catalog (key + label + valueTable + fkColumn) so an admin UI or add-on tool can enumerate the entity types without hard-coding the list.

### Admin UI

The admin Custom Fields page (`/agent/admin/custom-fields`) carries an entity-type picker. The URL query string `?entityType=contact` (etc.) selects which catalog to manage; all CRUD actions inherit that scope.

## Entity extension tables

For data that does **not** fit the typed-column custom-field shape (e.g. a foreign issue key, a sync timestamp, a JSON payload), an add-on can attach its own table to a core entity. Phase 9.2 defines the convention.

**Naming.** The table is `<parent_table>_<safe_addon_id>`, where the parent table is `tickets`, `contacts`, `organizations`, or `kb_articles`. The add-on id is normalized: hyphens become underscores; only `[a-z0-9_]` is allowed, starting with a letter. Example: add-on `example-jira` extending tickets → `tickets_example_jira`.

**Schema requirements.** Every extension table must:

1. Carry the FK column matching the parent (e.g. `ticket_id` referencing `tickets(id)` `ON DELETE CASCADE`). Recommended pattern: make the FK the primary key, one row per parent entity.
2. Carry an `organization_id` column (nullable for tickets, since accountless tickets exist; required for other entities).
3. Define whatever add-on columns it needs.

**Add-on migration template:**

```
var ext = wirebox.getInstance( "EntityExtensionService@core" );
schema.create( ext.tableNameFor( "ticket", "example_jira" ), function( table ){
    table.string( "ticket_id", 36 ).primaryKey().references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );
    table.string( "organization_id", 36 ).nullable().references( "id" ).onTable( "organizations" );
    table.string( "jira_issue_key", 50 );
    table.timestamp( "synced_at" ).nullable();
} );
```

### Service contract

`EntityExtensionService@core` is the sanctioned read/write path:

```
var ext = wirebox.getInstance( "EntityExtensionService@core" );

ext.upsertRow(
    coreEntityType : "ticket",
    entityId       : ticket.getId(),
    addonId        : "example_jira",
    organizationId : ticket.getOrganizationId() ?: "",
    data           : {
        jira_issue_key : "ACME-42",
        synced_at      : now()
    }
);

var row = ext.getRow(
    coreEntityType : "ticket",
    entityId       : ticket.getId(),
    addonId        : "example_jira",
    organizationId : viewer.organizationId
);

ext.deleteRow(
    coreEntityType : "ticket",
    entityId       : ticket.getId(),
    addonId        : "example_jira"
);
```

`upsertRow` injects the FK and `organization_id` columns; the add-on supplies the rest in `data`. The DB-level `ON CONFLICT ( <fk> ) DO UPDATE` requires the FK to be the primary key (or unique).

### Tenancy

`getRow` enforces tenancy when `organizationId` is passed: a row whose `organization_id` does not match returns null. A row whose `organization_id` is null (e.g. an accountless ticket) is surfaced to the caller; the caller decides whether to expose it (provider agents may see it; client surfaces never should).

### Per-request cache

Reads are cached in `request.tbxExtensionCache` so a handler that reads the row, then renders a view that also reads it, only hits Postgres once. Writes invalidate the cache key. The cache is per-request, not application-scoped: there is no cross-request invalidation problem.

---

## Notification templates

The notifications module ships two registries: `NotificationTemplateRegistry@notifications` for the per-event message templates and `NotificationChannelRegistry@notifications` for the delivery channels (in-app, email, slack, plus add-on channels).

Templates are keyed on the tuple `(event_key, channel, recipient_type)`. The `notification_templates` DB table is the **overrides** layer; the registry is the **defaults** layer. When `NotificationsService.dispatchForEvent` resolves the template set for an event, it overlays the DB rows on top of the registry seeds, so an admin-edited template wins, and a tuple that has no DB row still delivers (the registry default takes over).

### Declaring a template

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.notificationTemplates = [
    {
        eventKey      : "exampleJira.issue_linked",
        channel       : "email",
        recipientType : "agent",
        titleTemplate : "Jira issue {{issueKey}} linked to ticket {{ticketNumber}}",
        bodyTemplate  : "{{authorLabel}} linked {{issueKey}} to ticket {{ticketNumber}}.",
        linkTemplate  : "{{appBaseUrl}}/agent/tickets/{{ticketId}}",
        placeholders  : [ "issueKey", "ticketNumber", "ticketId", "authorLabel" ]
    }
];
```

| Field           | Required    | Notes                                                                          |
| --------------- | ----------- | ------------------------------------------------------------------------------ |
| `eventKey`      | yes         | Must match the event key your interceptor or service announces.                |
| `channel`       | yes         | Must be a registered channel id (see below).                                   |
| `recipientType` | yes         | `agent` or `contact`.                                                          |
| `titleTemplate` | yes         | Notification title / email subject / slack header.                             |
| `bodyTemplate`  | yes         | Notification body / email body / slack body.                                   |
| `linkTemplate`  | recommended | Deep link; empty string when not applicable.                                   |
| `placeholders`  | optional    | Array of token names the template references. Documentation only at runtime.  |

`{{appBaseUrl}}` and `{{unsubscribeUrl}}` are injected by the dispatcher and available in every template.

### Public extension contract

```
var registry = wirebox.getInstance( "NotificationTemplateRegistry@notifications" );
var all      = registry.listAll();
var byEvent  = registry.listForEvent( "ticket.created" );
var single   = registry.findTemplate( "ticket.created", "inapp", "agent" );
```

## Notification channels

Three channels ship out of the box: `inapp` (the bell dropdown), `email` (cbmailservices + admin-managed mail override), and `slack` (Slack/Teams incoming webhook via the `SLACK_WEBHOOK_URL` setting). Each is a thin class that conforms to the `INotificationChannel` contract.

### The contract

`INotificationChannel` is documented inline at `modules_app/notifications/models/contracts/INotificationChannel.bx`. The four methods:

| Method                | Returns | Purpose                                                                                                 |
| --------------------- | ------- | ------------------------------------------------------------------------------------------------------- |
| `getChannelId()`      | string  | Stable id (e.g. `email`). Matches the `channel` field on template rows.                                 |
| `getDisplayName()`    | string  | Human label for the admin UI and per-user preferences page.                                             |
| `send( notification )`| void    | Deliver one persisted Notification. Mutate `status` to `sent` or `failed`, save before returning.       |
| `supportsBatch()`     | boolean | Reserved. Return false; the dispatcher today calls `send()` once per recipient.                         |

Implementations are WireBox singletons so per-channel state (HTTP client, cached settings) stays scoped to the channel class.

### Declaring an add-on channel

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.notificationChannels = [
    {
        id          : "sms",
        displayName : "SMS",
        wirebox     : "TwilioSmsChannel@addon-twilio"
    }
];
```

`wirebox` is the WireBox alias of your channel implementation. The channel registry resolves the alias when dispatching.

| Field         | Required | Notes                                                                |
| ------------- | -------- | -------------------------------------------------------------------- |
| `id`          | yes      | Stable channel id; must match what your templates declare as `channel`. |
| `displayName` | yes      | Label rendered in the per-user preferences UI.                        |
| `wirebox`     | yes      | WireBox alias of the implementation class.                            |

Once the channel is registered, write a template for it via `settings.tesserabx.notificationTemplates`, and any event whose dispatched recipients have an enabled preference on that channel will be delivered through your `send()`.

### What the dispatcher does

For each `(recipient, channel)` pair:

1. Look up the template (DB overrides over registry defaults).
2. Skip if the channel id is not registered.
3. Skip if the recipient has set `notification_preferences.enabled = false` for that `(event, channel)`.
4. Build the per-recipient context (`{{appBaseUrl}}`, `{{unsubscribeUrl}}`), render title / body / link.
5. Persist a `Notification` row in status `pending` (or `sent` for `inapp`).
6. Hand off to `channelRegistry.send( channelId, notification )`, which resolves your implementation and calls its `send()`.

The dispatcher tolerates unknown channels and missing templates without throwing; either condition silently skips that fan-out leg.

### Public extension contract

```
var registry = wirebox.getInstance( "NotificationChannelRegistry@notifications" );
var all      = registry.listAll();
var ok       = registry.isRegistered( "email" );
var impl     = registry.resolve( "email" );           // returns the channel class
registry.send( "email", notification );               // deliver one row
```

---

## Help pages and sections

The `help` module is itself an extension point. Every core module and every add-on contributes pages and sections to the in-app help system at `/help` (portal) and `/agent/help` (agent).

Pages are markdown files that live alongside the module that contributes them. The help module reads them at request time and renders through `bx-markdown`, so an edit to a page's `.md` file lands the next time the page is loaded; no reinit required.

### Declaring a section

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.helpSections = [
    {
        id         : "billing",
        title      : "Billing",
        audience   : "agent",
        sortWeight : 500,
        icon       : "bi bi-receipt"
    }
];
```

| Field        | Required    | Notes                                                                          |
| ------------ | ----------- | ------------------------------------------------------------------------------ |
| `id`         | yes         | Stable identifier, conventionally one word.                                    |
| `title`      | yes         | Human label for the section landing.                                           |
| `audience`   | yes         | `public`, `client`, `agent`, or `developer`.                                   |
| `sortWeight` | recommended | Lower sorts first. Default 500.                                                |
| `icon`       | recommended | Bootstrap-icon class (e.g. `bi bi-receipt`).                                   |

### Declaring a page

```
settings.tesserabx.helpPages = [
    {
        id         : "billing.creating-an-invoice",
        section    : "billing",
        title      : "Creating an invoice",
        audience   : "agent",
        sortWeight : 10,
        source     : "resources/help/billing/creating-an-invoice.md",
        searchable : true,
        keywords   : [ "invoice", "billing", "charge" ]
    }
];
```

| Field        | Required    | Notes                                                                                |
| ------------ | ----------- | ------------------------------------------------------------------------------------ |
| `id`         | yes         | Stable identifier, conventionally `<section>.<slug>`.                                |
| `section`    | yes         | Must match a registered section id.                                                  |
| `title`      | yes         | Page title.                                                                          |
| `audience`   | yes         | `public`, `client`, `agent`, or `developer`. Cannot be broader than the section.     |
| `sortWeight` | recommended | Lower sorts first within the section. Default 500.                                   |
| `source`     | yes         | Module-relative path to the markdown file.                                           |
| `searchable` | recommended | Default true. Set false to exclude from search results.                              |
| `keywords`   | optional    | Extra search terms beyond the title and body content.                                |

### Audience model

The four audiences form a hierarchy. Any signed-in agent can see public and client pages too; any user with `help.developer` permission can see everything.

| Audience    | Who sees it                                       |
| ----------- | ------------------------------------------------- |
| `public`    | Anyone (anonymous portal visitors included).      |
| `client`    | Signed-in contacts on the portal, and all agents. |
| `agent`     | Signed-in agents on the provider dashboard.       |
| `developer` | Agents with the `help.developer` permission.      |

`help.developer` is auto-granted to the `agent-admin` role; grant it to other roles via the admin Users page.

### Search

Search is wired through Phase 7's `EmbeddingConsumerRegistry`. When `AI_ENABLED=true`, search runs a vector similarity comparison via the help-page embeddings; when off, the same box runs a substring + keyword match over title, declared `keywords`, and body text. Audience filtering applies AFTER ranking either way, so a page above the viewer's audience never appears in results. The user-facing search box is identical in both modes.

### EXTENSIONS.md download

The `/agent/help/download/extensions.md` endpoint streams the live `docs/EXTENSIONS.md` file to any agent with `help.developer`. The same content is rendered inline as the Module Development section's per-chapter pages; the download is for grabbing the whole doc at once.

### Public extension contract

```
var pageReg     = wirebox.getInstance( "HelpPageRegistry@help" );
var sectionReg  = wirebox.getInstance( "HelpSectionRegistry@help" );
var resolver    = wirebox.getInstance( "HelpAudienceResolver@help" );

var allSections = sectionReg.listAll();
var pagesInDev  = pageReg.listForSection( "development" );
var canSee      = resolver.canSeePage( viewer, page );
```

---

## What is not yet documented here

Later phases of the extensibility plan add sections to this file as they land:
- **Phase 12**: reference sample add-on and Quick start.

See [`docs/EXTENSIBILITY-PLAN.md`](EXTENSIBILITY-PLAN.md) for the full plan.
