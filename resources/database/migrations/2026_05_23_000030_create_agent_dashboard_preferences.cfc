/**
 * Create agent_dashboard_preferences: per-agent layout and visibility
 * overrides for the dashboard widget registry.
 *
 * Separate from registry_overrides because that table is the
 * org-wide admin override surface (sort weight, label, disable
 * globally or per-organization). This table is the per-agent
 * customisation layer that lets each agent reorder and hide widgets
 * on their personal /agent home dashboard.
 *
 * Resolution rule (implemented in DashboardWidgetRegistry.listForViewer):
 *   1. Start with the in-code or manifest entry.
 *   2. Apply registry_overrides (global, then per-org).
 *   3. Apply the visibility / permission / capability filters.
 *   4. Apply this table's per-agent override for the requesting viewer:
 *      - hidden=true: drop the entry.
 *      - sort_order set: replace the entry's sortWeight.
 *   5. Sort and return.
 *
 * The "zone" column matches the registry's zone field ("agent-home",
 * "reports", etc.) so the same table can hold overrides for any
 * dashboard surface an agent personalises.
 */
component {

    function up( schema, qb ){
        schema.create( "agent_dashboard_preferences", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "agent_id", 36 ).references( "id" ).onTable( "agents" ).onDelete( "CASCADE" );
            table.string( "zone", 50 );
            table.string( "widget_id", 200 );
            // Null = no override on sort order; use the entry's default.
            table.integer( "sort_order" ).nullable();
            table.boolean( "hidden" ).default( false );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "agent_id", "zone", "widget_id" ], "uq_agent_dash_pref_agent_zone_widget" );
            table.index( [ "agent_id", "zone" ], "idx_agent_dash_pref_agent_zone" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "agent_dashboard_preferences" );
    }

}
