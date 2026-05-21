/**
 * Create registry_overrides: shared admin-override layer for the
 * navigation / admin-pages / ticket-panel / dashboard-widget registries
 * (and any future Phase 4-style registry).
 *
 * Resolution rule (implemented in each registry's `applyOverrides`):
 *   1. Start with the in-code registration declared by the owning
 *      module or add-on.
 *   2. Look up override rows for ( registry, entry_id ).
 *   3. Apply the row whose organization_id matches the request tenant,
 *      else the row whose organization_id IS NULL (global override),
 *      else use the in-code values as-is.
 *
 * Override columns are intentionally narrow: disable an entry, change
 * its sort weight, change its label, or pass a freeform payload for
 * the registry-specific override semantics. Anything more requires a
 * code change to the underlying registry's resolution path.
 */
component {

    function up( schema, qb ){
        schema.create( "registry_overrides", function( table ){
            // Logical name of the registry the override applies to.
            // One of: "navigation", "admin_pages", "ticket_panels",
            // "dashboard_widgets", or any add-on-defined value.
            table.string( "registry", 50 );
            // The registered entry's id (e.g., "tickets.main",
            // "admin.users", "panel.sla"). The owning registry is
            // responsible for keeping ids stable across releases.
            table.string( "entry_id", 200 );
            // Nullable for global override; non-null for per-tenant.
            // No FK to organizations because an override may outlive
            // the tenant (rare, but the admin UI cleans these up).
            table.string( "organization_id", 36 ).nullable();
            table.boolean( "disabled" ).default( false );
            // Null = inherit from in-code declaration.
            table.integer( "sort_weight_override" ).nullable();
            table.string( "label_override", 255 ).nullable();
            // Freeform JSON for per-registry extensions; e.g., a
            // dashboard widget could override its grid size here.
            table.text( "payload" ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
            table.string( "updated_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
        } );

        // Postgres treats NULL values as distinct in a unique
        // constraint, so we need TWO partial unique indexes to enforce
        // "at most one row per (registry, entry_id, organization_id)":
        //   - one for the global override (organization_id IS NULL)
        //   - one for per-tenant overrides
        queryExecute(
            "CREATE UNIQUE INDEX uq_registry_overrides_global
             ON registry_overrides ( registry, entry_id )
             WHERE organization_id IS NULL"
        );
        queryExecute(
            "CREATE UNIQUE INDEX uq_registry_overrides_per_org
             ON registry_overrides ( registry, entry_id, organization_id )
             WHERE organization_id IS NOT NULL"
        );
        queryExecute( "CREATE INDEX idx_registry_overrides_registry ON registry_overrides ( registry )" );
        queryExecute( "CREATE INDEX idx_registry_overrides_org      ON registry_overrides ( organization_id )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS uq_registry_overrides_global" );
        queryExecute( "DROP INDEX IF EXISTS uq_registry_overrides_per_org" );
        queryExecute( "DROP INDEX IF EXISTS idx_registry_overrides_registry" );
        queryExecute( "DROP INDEX IF EXISTS idx_registry_overrides_org" );
        schema.drop( "registry_overrides" );
    }

}
