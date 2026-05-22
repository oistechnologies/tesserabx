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

