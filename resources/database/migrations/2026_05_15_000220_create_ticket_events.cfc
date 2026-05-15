/**
 * Create ticket_events: the per-ticket timeline.
 *
 * Distinct from audit_events. The audit log is the cross-module
 * compliance trail; ticket_events is the agent-facing ticket
 * history (status changes, assignments, reassignments, message
 * sent, etc.) shown inline on the ticket detail view.
 *
 * Significant ticket events also write to audit_events; that
 * coexistence is intentional per CLAUDE.md.
 */
component {

    function up( schema, qb ){
        schema.create( "ticket_events", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "ticket_id", 36 ).references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );

            table.string( "event_type", 50 );
            table.string( "actor_type", 50 ).nullable();
            table.string( "actor_id", 36 ).nullable();
            table.text( "metadata_json" ).nullable();

            table.timestamp( "occurred_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "ticket_id" );
            table.index( "event_type" );
            table.index( "occurred_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "ticket_events" );
    }

}
