/**
 * Create agent_filter_preferences: per-agent saved defaults for the
 * filter controls on agent screens.
 *
 * Currently used by /agent/tickets for the status checkbox group,
 * where each row stores ( agent_id, filter_key="statuses", value=
 * comma-delimited list of TicketStatus keys ). The schema is shaped
 * to extend without migration: future filter_keys like "priorities"
 * or "organization_ids" can land in the same table.
 *
 * Resolution chain (see AgentFilterPreferencesService.resolveDefaultStatuses):
 *   1. This row, when one exists for ( agent_id, "statuses" ).
 *   2. SettingsService "tickets.default_filter_statuses" admin global.
 *   3. WorkflowService.keysByCategory( [ "open", "paused" ] ).
 *
 * Stored as plain text (comma-delimited) rather than jsonb because
 * Quick's .save() rebinds every column on an entity carrying a
 * PGobject, which breaks the unrelated save paths. Text avoids the
 * PGobject pathway entirely.
 */
component {

    function up( schema, qb ){
        schema.create( "agent_filter_preferences", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "agent_id", 36 ).references( "id" ).onTable( "agents" ).onDelete( "CASCADE" );
            table.string( "filter_key", 50 );
            table.text( "value" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "agent_id", "filter_key" ], "uq_agent_filter_pref_agent_key" );
            table.index( [ "agent_id" ], "idx_agent_filter_pref_agent" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "agent_filter_preferences" );
    }

}
