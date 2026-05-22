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

### Entity-level shortcuts

The base `TesseraBXEntity` class exposes typed shortcut methods so add-on code does not have to drive `CustomFieldsService` directly for one-off reads:

```boxlang
ticket.getCustomFieldValue( "external_jira_key" )    // returns the typed value, or null
ticket.getCustomFieldValues()                        // { key : typedValue, ... } across every active definition
ticket.setCustomFieldValue( "external_jira_key", "JIRA-1234", actorAgentId )
```

The four core entities (`Ticket`, `Contact`, `Organization`, `Article`) participate out of the box. Each declares its entity-type key via:

```boxlang
public string function customFieldEntityType(){ return "ticket"; }
```

Add-on entities that ship custom-field-style metadata can override the same hook to opt in. Entities that do not override (e.g. join tables, value records) inherit the empty default; the getters return null / `{}`, and `setCustomFieldValue` throws `TesseraBXEntity.CustomFieldsNotSupported`.

Typed return values:

| Field type      | `getCustomFieldValue` returns                        |
| --------------- | ---------------------------------------------------- |
| text / textarea | the saved string, or `""` if unset                   |
| select          | the saved option value, or `""` if unset             |
| number          | a numeric value, or null if unset                    |
| date            | a date value, or null if unset                       |
| boolean         | a real boolean (false when unset)                    |

`setCustomFieldValue` throws `TesseraBXEntity.UnknownCustomFieldKey` when the key does not match an active definition; blind writes are almost always a bug. Use `CustomFieldsService.setValuesFor` directly when batch-saving the full form.

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

