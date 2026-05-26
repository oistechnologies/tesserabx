# TesseraBX Extensions Guide

TesseraBX is extensible by third-party BoxLang ColdBox modules. A developer can ship an "add-on" as a standard ColdBox module, install it into a running TesseraBX deployment, and contribute navigation items, admin pages, ticket panels, dashboard widgets, channel adapters, automation actions, AI features, API routes, roles, custom field types, notification templates, and help pages, all without modifying core code.

This guide is the contract that add-on authors code against and the operator's reference for managing add-ons in a TesseraBX install. The companion [`docs/EXTENSIBILITY-PLAN.md`](EXTENSIBILITY-PLAN.md) is the phased plan for landing this contract; this file documents the full contract as it stands today (every phase 0-12 has shipped).

A complete working example lives in [`sample-addons/example-sync/`](../sample-addons/example-sync). It exercises every registry and contract documented here; its `tests/specs/InstallSpec.bx` runs in CI as the integrity check that the contract has not regressed.

---

## Quick start: build your first add-on

1. **Scaffold.** Run `box tesserabx:scaffold-addon <slug>`. A skeleton module lands at `modules/<slug>/` with a passing `InstallSpec`.
2. **Edit the manifest.** Open the new module's `ModuleConfig.bx` and find the `settings.tesserabx` block. Add the contributions you want (see the tables of contents below to find each contract).
3. **Re-run the InstallSpec.** Restart the container, run `box testbox run bundles=modules.<slug>.tests.specs.InstallSpec`. Every registered contribution should land in the right core registry.
4. **Test in the browser.** Reload the app. Nav entries appear in their menu zones, admin cards land on `/agent/admin`, ticket panels appear in the ticket detail right column, etc.

The fastest path to a working add-on is to copy [`sample-addons/example-sync/`](../sample-addons/example-sync) and rename the slug everywhere (the literal string `example-sync` / `exampleSync` / `example_sync` are the only places the slug appears in identifier form).

---

## Contents

- [What an add-on is](#what-an-add-on-is)
- [Manifest fields](#manifest-fields)
- [Discovery](#discovery)
- [Enablement resolution](#enablement-resolution)
- [Scaffolding a new add-on](#scaffolding-a-new-add-on)
- [Service contracts](#service-contracts)
- [DTOs](#dtos)
- [Tenant scope](#tenant-scope)
- [Add-on migrations](#add-on-migrations)
- [Per-tenant settings](#per-tenant-settings)
- [Events](#events)
- [Audit-event contributions](#audit-event-contributions)
- [Roles and permissions](#roles-and-permissions)
- [Navigation](#navigation)
- [Route claims](#route-claims)
- [Admin pages](#admin-pages)
- [Ticket detail panels](#ticket-detail-panels)
- [Dashboard widgets](#dashboard-widgets)
- [Asset publishing](#asset-publishing)
- [Override table for UI registries](#override-table-for-ui-registries)
- [Channel adapters](#channel-adapters)
- [Automation: triggers, conditions, and actions](#automation-triggers-conditions-and-actions)
- [AI features, providers, and embeddings](#ai-features-providers-and-embeddings)
- [API resources](#api-resources)
- [Webhook events](#webhook-events)
- [Custom fields](#custom-fields)
- [Entity extension tables](#entity-extension-tables)
- [Notification templates](#notification-templates)
- [Notification channels](#notification-channels)
- [Email templates](#email-templates)
- [Sending email from an add-on](#sending-email-from-an-add-on)
- [Help pages and sections](#help-pages-and-sections)

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

Add-ons ship migrations in their own tree. The `tasks/Migrate.cfc` CommandBox task discovers them and stages each file into the central directory that `cfmigrations` scans, so the standard runner picks them up without any cfmigrations config changes.

**Where to put migrations in an add-on:**

```text
modules/<slug>/migrations/<timestamp>_<name>.cfc          (canonical for ForgeBox add-ons)
modules/<slug>/resources/migrations/<timestamp>_<name>.cfc
sample-addons/<slug>/migrations/<timestamp>_<name>.cfc    (in-tree sample add-ons)
modules_app/<slug>/migrations/<timestamp>_<name>.cfc      (first-party split-outs)
modules_app/<slug>/resources/migrations/<timestamp>_<name>.cfc
```

The task walks all of these and stages every `.cfc` it finds.

**Running migrations:**

```text
box run-script migrate:up        # stage then run pending migrations
box run-script migrate:down      # stage then roll back one
box run-script migrate:fresh     # stage, drop everything, then re-run
box run-script migrate:refresh   # stage, down all, then up all
box run-script migrate:stage     # stage only (dry-run; no migrations executed)
```

These are aliases in `box.json` that delegate to `box task run tasks/Migrate <subcommand>`. Plain `box migrate up` still works against the central dir, but you have to remember to run the stager first.

**Staging convention:**

Each discovered file is copied into `resources/database/migrations/<timestamp>_addon-<slug>_<rest>.cfc`, where `<timestamp>` is the original `YYYY_MM_DD_HHmmss` prefix and `<rest>` is everything after it in the source filename. For example, `modules/tesserabx-pm/migrations/2026_05_24_120000_create_pm_projects.cfc` stages as `resources/database/migrations/2026_05_24_120000_addon-tesserabx-pm_create_pm_projects.cfc`.

The hyphen between `addon-` and the slug is intentional:

- it is the sentinel `.gitignore` matches on (`resources/database/migrations/*_addon-*_*.cfc`), so staged copies are runtime artifacts and never committed
- it visually distinguishes staged add-on files from hand-written core migrations (whose names contain only underscores, e.g. `2026_05_20_000010_create_addon_tables.cfc`)
- it uniquely namespaces the component name in the global `cfmigrations` table when two add-ons happen to pick the same timestamp
- it is left alone on re-stage (idempotent)

The timestamp MUST stay at the front of the staged filename because `cfmigrations` inspects only the first 10 characters and requires them to parse as a date. A previous layout that placed the `_addon-<slug>_` prefix before the timestamp was silently filtered out of every `box migrate up`, so add-on migrations never ran in CI.

The stager writes `resources/database/migrations/.staged.json` listing every staged file plus its source, so an operator can audit what came from where.

**Conventions you still own:**

1. Use the timestamped sortable format core uses (`YYYY_MM_DD_HHmmss_<name>.cfc`). The timestamp drives cfmigrations sort order.
2. Use the standard component declaration: `component { function up( schema, qb ){...}; function down( schema, qb ){...}; }`.
3. Every per-tenant table MUST include an `organization_id` column with a FK and `ON DELETE CASCADE`, and the entity that fronts the table MUST apply `TenantScope@contacts`.

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

As of follow-up B3, the four pre-Phase-3 events emit the canonical envelope alongside the original entity-keyed payload. Existing listeners that read `interceptData.ticket`, `interceptData.message`, `interceptData.article`, `interceptData.from`, `interceptData.to`, or `interceptData.accountless` keep working unchanged; new listeners (and add-ons) should prefer the canonical fields:

- `onTicketCreated`: envelope `+ { ticket : <Quick entity>, accountless : boolean }`. `entity = { type : "Ticket", id }`. `after = ticket DTO`. `metadata.accountless` mirrors the top-level flag.
- `onTicketMessageAdded`: envelope `+ { message : <Quick entity>, ticket : <Quick entity> }`. `entity = { type : "TicketMessage", id }`. `after = message DTO`. `metadata = { ticketId, isInternal }`.
- `onTicketStatusChanged`: envelope `+ { ticket : <Quick entity>, from : "...", to : "..." }`. `entity = { type : "Ticket", id }`. `before = { status : <from> }`. `after = ticket DTO`. `metadata = { from, to }`.
- `onKbArticlePublished`: envelope `+ { article : <Quick entity> }`. `entity = { type : "Article", id }`. `after = article snapshot` (id, slug, title, visibility, status, publishedAt). `metadata = { version }`.

The canonical fields (`entity`, `before`, `after`, `metadata`) are JSON-serializable structs. The legacy top-level entity keys still carry the live Quick instance, so a listener that needs to call entity methods directly does not have to round-trip through the service layer. A future migration may drop the legacy keys; until then, both shapes coexist.

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

## Route claims

Sometimes an add-on needs to claim a top-level URL that does not fall under its own `entryPoint`. Examples: a Project Management add-on wants `/agent/pm` (lives on the agent surface), `/pm` (lives on the portal surface), and `/agent/admin/pm` (lives inside the admin module's URL space) — none of those URLs are reachable from a module Router whose `entryPoint = "tesserabx-pm"` because ColdBox 8 auto-prefixes every route declared in a module Router with the module's `entryPoint`.

The `routeClaims` manifest contract is the supported way for an add-on to bind handlers at arbitrary top-level URLs:

```boxlang
settings.tesserabx.routeClaims = [
    {
        path    : "/agent/pm",          // required, must start with /
        verbs   : "GET",                // optional, defaults to any verb
        module  : "tesserabx-pm",       // required, module that owns the handler
        handler : "Main",               // required, handler name within the module
        action  : "index",              // required, action method on the handler
        name    : "pm.agent.landing"    // optional, ColdBox named route
    },
    { path : "/pm",             module : "tesserabx-pm", handler : "Main", action : "index" },
    { path : "/agent/admin/pm", module : "tesserabx-pm", handler : "Main", action : "index" }
];
```

**How it works:**

1. `RouteClaimsRegistry@core` walks every loaded module's manifest at boot and validates each `routeClaims` entry (must be a struct with non-empty `path`, `module`, `handler`, and `action`; path must start with `/`). Invalid claims are skipped with a warning logged to the `tesserabx` log.
2. The `AddonRouteClaimsRegistrar` interceptor listens for `afterAspectsLoad` and, for each valid claim, calls `controller.getRoutingService().getRouter().addRoute(...)` with `append=false` so the claim is **prepended** to the routes array. This guarantees the claim matches before the host's catch-all `:handler/:action?`.
3. The resulting ColdBox event string composes as `<module>:<handler>.<action>` (the same format the host uses to route across modules in its own `config/Router.bx`, e.g. `route("/login").to("portal:Session.new")`).
4. The claimed URL inherits whatever `cbSecurity` firewall covers its path prefix. `/agent/pm` rides the agent firewall (auth required), `/pm` rides the portal firewall, `/agent/admin/pm` rides the admin firewall. The add-on does not need to declare its own cbSecurity rules just because a route claim sits inside another surface.

**When to use it:** when the URL you want is on another surface (agent vs portal), inside another module's entry-point space (e.g. `/agent/admin/*`), or otherwise unreachable from your own module Router. Most add-ons will not need route claims; their internal URLs live happily under their own entry point.

**When NOT to use it:** if you just want a URL like `/<your-slug>/something`, declare it normally inside your add-on's `config/Router.bx`. Route claims are deliberately the heavier path because every claim is a hand-edited entry in a host-wide registry; declarations inside the module Router are the cheaper default.

**Validation:** the `InstallSpec` shipped with each add-on should probe `RouteClaimsRegistry@core.findByPath( path )` for every claim to catch a silently-dropped registration (typo in a required field, missing path slash, etc.).

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

Same shape for both dashboard surfaces:

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
        requiredPermission : "exampleJira.view",
        zone               : "reports"                              // optional, see below
    }
];
```

### Zones

Each widget belongs to a `zone`. Two zones are supported:

| Zone         | Surface          | Audience                                                                                                                                                  |
|--------------|------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `reports`    | `/agent/reports` | The org-wide aggregate dashboard. Widgets here typically show counts across all organizations and agents. This is the default when `zone` is omitted.     |
| `agent-home` | `/agent`         | The agent's personal landing page. Widgets here are scoped to the logged-in agent (their tickets, their mentions, their activity, etc.).                  |

An add-on opts into a surface by declaring `zone` on each widget entry. Omit `zone` (or set it to `"reports"`) to contribute to `/agent/reports`. Set `zone : "agent-home"` to contribute to the agent's personal home page. Add-ons can declare widgets in both zones by registering one entry per zone.

The host loops `#tbxDashboardWidgets( "reports" )#` (or `tbxDashboardWidgets( "agent-home" )`), invokes each widget's data provider (when declared), and renders the named partial wrapped in the declared grid size. The same deferral applies on the `reports` zone: core's existing six dashboard widgets (overview tiles, ticket-volume line chart, three doughnut charts, backlog table, agent-load table) remain rendered inline and are not yet migrated to the registry.

### Reusable `.small-box` partial

For KPI-style widgets (one big number + a label), the core module ships a partial that renders the AdminLTE 4 [`.small-box`](https://adminlte.io/themes/v4/dist/widgets/small-box.html). Adopt it so add-on widgets look like core widgets:

```boxlang
<bx:output>
#view( view = "_partials/small_box", module = "core", args = {
    color     : "primary",                       // primary | success | warning | danger | info | secondary
    metric    : encodeForHTML( prc.widgetData.openCount ),
    label     : "Open Jira issues",
    icon      : "bi bi-bug",                     // any Bootstrap Icon class
    caption   : "synced 5 min ago",              // optional secondary line
    link      : "/agent/admin/example-jira",     // optional footer link; omit for no footer
    linkLabel : "Manage sync"                    // optional, defaults to "View details"
} )#
</bx:output>
```

Caller responsibilities: HTML-encode any user-supplied values you pass in `metric` (the partial does not, so you can compose markup like `<small>%</small>`). Pass any of the six Bootstrap semantic color tokens for `color`; `warning` automatically gets a dark footer link, the others get light.

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

## Email templates

A notification template (above) is enough to deliver a fully working branded email. The core `MailComposerService@core` reads each notification's plain-text `bodyTemplate`, auto-renders it to HTML (paragraphs, links), wraps it in the configured brand chrome, and ships both an HTML and a plain-text part. Your add-on does not have to know any of that.

For the cases where the auto-render is not enough, an add-on can ship its own body view as a `.bxm` partial and point at it through an *email template* entry. The composer renders that partial as the inner body and keeps the surrounding chrome from the core layout.

Use email templates when:

- You want a structured layout (data table, metadata card, call-to-action button) the auto-render cannot produce from plain text.
- You want to embed brand-specific imagery the chrome does not already pull in.
- You want different copy at different breakpoints by adding inline `@media` rules inside your partial.

### What an email template is

An email template is a `{ id, displayName, subject, module, partial, placeholders }` entry declared in `settings.tesserabx.emailTemplates`. The `module` and `partial` together resolve to a ColdBox view (a `.bxm` file under your add-on's `views/`) that the composer renders as the inner body of the email. The partial receives a fixed set of variables in `args` (see *Where the partial lives* below).

This is **distinct from a notification template**: a notification template is the event-driven message body that the dispatcher resolves automatically when an event fires; an email template is an opt-in body view your add-on can name and have the composer render, typically from a dedicated send path.

### Declaring an email template

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.emailTemplates = [
    {
        id           : "issueLinkedDigest",
        displayName  : "Issue-linked digest",
        subject      : "Daily digest: {{linkedCount}} ticket links",
        module       : "example-sync",
        partial      : "emails/issue_linked_digest",
        placeholders : [ "linkedCount", "appBaseUrl", "productName" ],
        requiresAi   : false
    }
];
```

| Field          | Required | Notes                                                                                                                  |
| -------------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| `id`           | yes      | Stable per-add-on identifier. Surfaces in the admin email-preview screen's template picker.                            |
| `displayName`  | yes      | Human label for the same picker.                                                                                       |
| `subject`      | yes      | Default subject line. May contain `{{token}}` placeholders the calling code substitutes before invoking the composer.  |
| `module`       | yes      | Your module name. The composer uses this when resolving the partial.                                                   |
| `partial`      | yes      | View path relative to your module's `views/` folder, without the `.bxm` suffix.                                        |
| `placeholders` | optional | Array of token names the partial references. Documentation only at runtime; the composer does not validate against it. |
| `requiresAi`   | optional | When `true`, the four UI registries hide this entry while `AI_ENABLED=false`. Default `false`.                          |

### Where the partial lives

The partial is a regular `.bxm` view inside your add-on, for example `views/emails/issue_linked_digest.bxm`. The composer renders it through `controller.getRenderer().renderView(...)` with these `args` in scope:

| Variable       | Type    | Notes                                                                          |
| -------------- | ------- | ------------------------------------------------------------------------------ |
| `brand`        | struct  | Resolved branding (`productName`, `tagline`, `logoUrl`, `primaryColor`, `footerText`). Per-org overrides already merged. |
| `tokens`       | struct  | The `tokens` argument the caller passed to `compose()`.                        |
| `appBaseUrl`   | string  | Absolute URL prefix. Use to build links inside the body.                       |
| `logoTarget`   | string  | Resolved absolute logo URL (configured value, or bundled default).             |
| `primaryColor` | string  | Normalized hex color, ready to inline as a `style="background:..."` value.     |
| `style`        | string  | `notification` or `reply`. Useful for partials that subtly adapt to either.    |
| `eventKey`     | string  | The `eventKey` argument; useful when one partial serves several events.        |
| `preheader`    | string  | Inbox-preview text. The wrapping layout renders this; partials can ignore it.  |

Constraint reminders for the partial:

- **Inline CSS only.** Email clients strip `<style>` blocks. The wrapping chrome controls fonts and the overall column width; your partial controls the inside.
- **Table-based layout** for any multi-column structure. Email clients flake on flexbox and grid.
- **No em dashes** anywhere in the partial (per the project's deliverable rule). Use commas, parentheses, or restructured sentences.

### Resolution and overrides

`EmailTemplateRegistry@core` reads `settings.tesserabx.emailTemplates` from every loaded module at boot and exposes:

```
var registry = wirebox.getInstance( "EmailTemplateRegistry@core" );
var all      = registry.listAll();                  // every registered template
var single   = registry.findById( "issueLinkedDigest" );
```

The admin email-preview screen (`/agent/admin/email-preview`) lists registered templates in the picker. v1 ships the registry as read-only; admin DB-side overrides are a follow-up.

### Public extension contract

What is stable for add-on authors:

- The shape of an `emailTemplates` array entry (the seven fields above).
- The `args` struct variables a body partial can rely on.
- `EmailTemplateRegistry@core.listAll()` and `findById( id )`.
- The wrapping chrome contract: your partial controls the inside; the composer wraps it in the layout selected by `style`.

What is not stable yet, and may change:

- The `placeholders` field. Today it is documentation; future versions may use it to validate that every declared token resolves to a non-empty value before send.
- The pool of in-scope variables in the partial. New ones may appear; existing ones will not be renamed without a deprecation cycle.

## Sending email from an add-on

Every outbound email in TesseraBX goes through the single `MailComposerService@core`. Add-ons inject it the same way as any other service and call `compose()` to produce a Mail object, then `send()` to ship it.

The composer takes care of: branding resolution (global vs per-organization), the HTML chrome, the plain-text alternative, the documented ops headers (`X-TesseraBX-Event`, `X-TesseraBX-Organization`), and the admin-managed SMTP override. Add-ons supply the recipient, subject, and body; everything else has a sensible default.

### The MailComposerService API

```
class {

    property name="mailComposer" inject="MailComposerService@core";

    function welcome( required any contact ){
        var mail = mailComposer.compose(
            to             : contact.getEmail(),
            subject        : "Welcome to support, {{name}}!",
            body           : "Hi {{name}},\n\nThanks for getting in touch. We are glad you are here.\n\nThe team",
            bodyFormat     : "text",
            recipientType  : "contact",
            organizationId : contact.getOrganizationId(),
            eventKey       : "myaddon.contact.welcome",
            tokens         : { name : contact.getFirstName() }
        );
        mailComposer.send( mail );
    }

}
```

`compose()` arguments worth knowing:

| Argument             | Default                  | Notes                                                                                                                |
| -------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `to`                 | required                 | Recipient address.                                                                                                   |
| `subject`            | required                 | Subject line. May contain unsubstituted `{{tokens}}`; substitute through `tokens` before the call.                   |
| `from`               | env `MAIL_FROM`          | Bare address. The composer wraps it with the `email.from_name` setting (or `brand.product_name`) as a friendly label. |
| `replyTo`            | `email.reply_to` setting | Reply-To header.                                                                                                     |
| `body`               | empty                    | Raw HTML (default) or plain text when `bodyFormat = "text"`.                                                         |
| `bodyFormat`         | `"html"`                 | Set to `"text"` to have the composer paragraphize on `\n\n`, auto-link URLs, and HTML-escape special chars.          |
| `bodyTemplate`       | `{}`                     | `{ module, partial }` reference to an add-on body partial (an email template entry).                                 |
| `layoutTemplate`     | `{}`                     | `{ module, partial }` to replace the wrapping chrome entirely. Rare; most add-ons leave this empty.                  |
| `style`              | `"notification"`         | `"notification"` (full chrome) or `"reply"` (thin chrome, person-to-person feel).                                    |
| `recipientType`      | `"raw"`                  | `"agent"`, `"contact"`, or `"raw"`. Drives the brand-resolution rule below.                                          |
| `organizationId`     | `""`                     | Tenant context. Required for per-organization branding to kick in.                                                   |
| `preheader`          | `email.preheader_default`| Inbox-preview text. Hidden in the rendered body, surfaces in the inbox list.                                         |
| `eventKey`           | `""`                     | Populates the `X-TesseraBX-Event` header.                                                                            |
| `listUnsubscribeUrl` | `""`                     | When non-blank and `style = "notification"`, emits the `List-Unsubscribe` and `List-Unsubscribe-Post` headers.        |
| `tokens`             | `{}`                     | Substitution data passed to a body partial; ignored when no `bodyTemplate` is set.                                   |
| `headers`            | `{}`                     | Arbitrary extra headers. Use for `Message-ID`, `In-Reply-To`, `References` when threading a ticket reply.            |
| `attachments`        | `[]`                     | Reserved for future use. Add attachments by mutating the returned Mail object directly until this lands.             |

### Composing without a custom template

If your add-on needs to send a one-off message and the auto-render is enough, skip `bodyTemplate` entirely and pass the body as either raw HTML or plain text:

```
// Plain-text body, auto-rendered to HTML
var mail = mailComposer.compose(
    to         : "user@example.com",
    subject    : "Welcome",
    body       : "Hi,\n\nWelcome aboard.\n\nThe team",
    bodyFormat : "text"
);
mailComposer.send( mail );

// Pre-rendered HTML body (caller built it)
var mail = mailComposer.compose(
    to         : "user@example.com",
    subject    : "Statement ready",
    body       : "<p>Your statement is ready.</p><p><a href=""...."">Download PDF</a></p>"
);
mailComposer.send( mail );
```

### Composing with a custom template

Declare the template in your manifest (see *Email templates* above), then point the composer at it through `bodyTemplate`:

```
var mail = mailComposer.compose(
    to             : agent.getEmail(),
    subject        : "Daily digest: " & linkedCount & " ticket links",
    bodyTemplate   : { module : "example-sync", partial : "emails/issue_linked_digest" },
    tokens         : {
        linkedCount : linkedCount,
        links       : recentLinks
    },
    recipientType  : "agent",
    eventKey       : "exampleSync.digest"
);
mailComposer.send( mail );
```

Inside `views/emails/issue_linked_digest.bxm`:

```
<bx:output>
<p style="margin:0 0 16px 0;">
    You linked <strong>#args.tokens.linkedCount#</strong> ticket(s) to external issues today.
</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
    <bx:loop array="#args.tokens.links#" item="row">
        <tr>
            <td style="padding:8px 0;border-bottom:1px solid ##eee;">
                #encodeForHTML( row.issueKey )# -> #encodeForHTML( row.ticketSubject )#
            </td>
        </tr>
    </bx:loop>
</table>
<p style="margin:16px 0 0 0;">
    <a href="#encodeForHTMLAttribute( args.appBaseUrl & '/agent/reports/issue-links' )#"
       style="background:#args.primaryColor#;color:##ffffff;text-decoration:none;padding:10px 16px;display:inline-block;border-radius:4px;">View report</a>
</p>
</bx:output>
```

### Brand context and recipient type

The composer resolves which brand to render with based on `recipientType` and `organizationId`:

| `recipientType` | `organizationId` | Brand source                                                                            |
| --------------- | ---------------- | --------------------------------------------------------------------------------------- |
| `agent`         | any              | Global (provider) brand. Agents see across organizations; the global brand is correct.  |
| `contact`       | empty            | Global brand. Unscoped recipient.                                                       |
| `contact`       | a tenant id      | Per-org brand merged over global. Per-org non-blank columns win; blanks fall through.   |
| `raw`           | empty            | Global brand. Unknown sender (accountless ticket, password-reset to a stranger).        |

You only need to set `organizationId` when sending to a `contact` and want their organization's branding overrides to apply. Setting it for an `agent` recipient is harmless; the composer will still pick the global brand.

### Headers and deliverability

Every email the composer produces carries these headers:

- `X-TesseraBX-Event` (when `eventKey` is non-blank): mirrors the event that triggered the send. Useful for filtering in the inbound matcher and for ops debugging.
- `X-TesseraBX-Organization` (always): the tenant id, or `unknown` when there is no tenant context.
- `From: "Friendly Name" <bare-address>`: friendly name resolved from `email.from_name` setting, then `brand.product_name`.

When you set `listUnsubscribeUrl` and `style = "notification"`, the composer additionally emits the RFC 8058 one-click unsubscribe headers:

- `List-Unsubscribe: <url>, <mailto:from?subject=unsubscribe>`
- `List-Unsubscribe-Post: List-Unsubscribe=One-Click`

Gmail and Outlook honor these for the native inbox unsubscribe button.

For threaded reply mail, pass `Message-ID`, `In-Reply-To`, and `References` through `headers`:

```
var mail = mailComposer.compose(
    to       : contact.getEmail(),
    subject  : "[Ticket ##" & ticket.getNumber() & "] Re: " & ticket.getSubject(),
    body     : reply,
    style    : "reply",
    eventKey : "tickets.agent_reply",
    headers  : {
        "Message-ID"  : ourGeneratedMessageId,
        "In-Reply-To" : ticket.getLatestInboundMessageId(),
        "References"  : ticket.getThreadReferencesHeader()
    }
);
```

### Sending vs queueing

`MailComposerService.send( mail )` is synchronous today. Call it directly when you want immediate delivery (and immediate error visibility). A future release will add a `composeAndQueue( ... )` path backed by cbq; switching to it will be a one-method swap on your call site, so call `composer.send( ... )` rather than reaching into cbmailservices directly.

### Public extension contract

What is stable for add-on authors:

- `MailComposerService@core` is the only documented send path for add-on mail.
- The `compose()` argument names listed above. Defaults may change; new optional arguments may appear.
- The `send()` wrapper.
- The two ops headers (`X-TesseraBX-Event`, `X-TesseraBX-Organization`).
- The `List-Unsubscribe` opt-in via `listUnsubscribeUrl`.

What is not stable yet:

- The `attachments` argument. Reserved; mutate the returned Mail object directly until it lands.
- The exact format of the friendly From label. The current `"Name" <addr>` shape works in every modern client; we may add an RFC 5322 encoder pass if non-ASCII names need it.
- Multipart shape. v1 emits `multipart/mixed` because bx-mail hardcodes that subtype; a future upstream fix or custom protocol will flip the outer to `multipart/alternative`. Both bodies are present and modern clients render correctly in either case.

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

## Reference add-on

A complete reference add-on lives at [`sample-addons/example-sync/`](../sample-addons/example-sync). It demonstrates every contract documented above: navigation across multiple menu zones, an admin connection page, a role + permission, a ticket right-column panel, a dashboard widget, a channel adapter, an automation action, an AI feature, an embedding consumer, REST API routes, a webhook event, an entity extension table, a per-tenant setting, a notification channel + template, audit event types, and two help pages (one agent-audience, one developer-audience).

Every external call in the add-on is stubbed (the channel adapter does not deliver, the API handler returns canned data, the AI feature returns placeholder text). What is real is the registration shape: a new add-on author can copy the directory, rename the slug, and have a working starting point that already hits every extension point with passing tests.

The add-on's `tests/specs/InstallSpec.bx` is the canary: it walks every core registry and asserts the example-sync contributions landed. The CI workflow runs it on every push so a regression to the extension contract fails the whole pipeline.

See [`docs/EXTENSIBILITY-PLAN.md`](EXTENSIBILITY-PLAN.md) for the full plan + the per-phase gotcha log.
