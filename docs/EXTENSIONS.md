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

## What is not yet documented here

Later phases of the extensibility plan add sections to this file as they land:
- **Phase 3**: the event catalog, canonical payload shape, and audit-event contributions.
- **Phase 4**: navigation, admin pages, ticket panels, dashboard widgets, asset publishing, and the role / permission registry.
- **Phase 5**: channel adapter contract.
- **Phase 6**: automation triggers, conditions, and actions.
- **Phase 7**: AI feature, provider, and embedding consumer registries.
- **Phase 8**: API resource registry, OpenAPI contribution, and webhook event registry.
- **Phase 9**: custom fields generalization and the entity-extension table convention.
- **Phase 10**: notification template registry and delivery channel plug-ins.
- **Phase 11**: help page and section registries (this guide will then also be rendered as an in-app help section).
- **Phase 12**: reference sample add-on and Quick start.

See [`docs/EXTENSIBILITY-PLAN.md`](EXTENSIBILITY-PLAN.md) for the full plan.
