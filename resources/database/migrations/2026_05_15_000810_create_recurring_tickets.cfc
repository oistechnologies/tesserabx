/**
 * Create recurring_tickets: templates for tickets the scheduler
 * creates on a cadence.
 *
 * Phase 3d ships the data model + service for materializing a ticket
 * from a template. Phase 3e wires the scheduled task that picks rows
 * whose next_run_at <= NOW() and runs them. `interval_minutes` is the
 * simple form (every N minutes); a cron column is left for Phase 5
 * if needed.
 *
 * organization_id and requester_contact_id are nullable so templates
 * can target an organization, a specific contact, or be unattached
 * (the resulting ticket starts as accountless until promoted).
 */
component {

    function up( schema, qb ){
        schema.create( "recurring_tickets", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.text(   "description" ).nullable();

            table.string( "organization_id", 36 ).nullable().references( "id" ).onTable( "organizations" ).onDelete( "SET NULL" );
            table.string( "requester_contact_id", 36 ).nullable().references( "id" ).onTable( "contacts" ).onDelete( "SET NULL" );
            table.string( "assigned_to_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );

            // What the materialized ticket looks like.
            table.string( "subject", 500 );
            table.text(   "body_template" ).nullable();
            table.string( "priority", 20 ).default( "normal" );
            table.string( "ticket_type", 20 ).default( "request" );
            table.string( "source", 20 ).default( "scheduler" );

            // Cadence. interval_minutes is the granular schedule; the
            // scheduler in Phase 3e adds intervalMinutes to last_run_at
            // (or to created_at when last_run_at is null) to compute the
            // next run. A negative or zero value disables the template
            // without deleting it.
            table.integer( "interval_minutes" ).default( 1440 );
            table.timestamp( "next_run_at" ).nullable();
            table.timestamp( "last_run_at" ).nullable();
            table.string( "last_ticket_id", 36 ).nullable();

            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "next_run_at" );
            table.index( "is_active" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "recurring_tickets" );
    }

}
