/**
 * Create tickets: the core help-desk record.
 *
 * organization_id and requester_contact_id are both NULLABLE because
 * Phase 1 supports accountless tickets (originating only from an
 * email address with no Contact yet). Such a ticket is visible only
 * to provider agents and sits outside the tenant scope. A promote-
 * sender-to-contact action backfills both columns and brings the
 * ticket under tenancy.
 *
 * ticket_number is a per-deployment monotonic integer for human
 * reference ("ticket #1042"); it lives alongside the UUID id rather
 * than replacing it so URLs and foreign keys stay stable across
 * resequencing.
 *
 * Status, priority, type, and source are stored as strings with a
 * default rather than as Postgres enums so the application can
 * evolve the enumerations without schema migrations.
 */
component {

    function up( schema, qb ){
        // Sequence backing ticket_number. Starts at 1000 so demo data
        // looks plausible from day one and accidental ID collisions
        // with manually-imported tickets stay unlikely.
        queryExecute( "CREATE SEQUENCE IF NOT EXISTS tickets_ticket_number_seq START 1000" );

        schema.create( "tickets", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.bigInteger( "ticket_number" ).default( "nextval('tickets_ticket_number_seq')" ).unique();

            // Tenant + requester. Both nullable for accountless tickets.
            table.string( "organization_id", 36 ).nullable().references( "id" ).onTable( "organizations" ).onDelete( "SET NULL" );
            table.string( "requester_contact_id", 36 ).nullable().references( "id" ).onTable( "contacts" ).onDelete( "SET NULL" );
            table.string( "assigned_to_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );

            // Inbound-email cross-reference. Always captured (even for
            // contact-backed tickets) so support traffic is traceable
            // back to the raw sender address.
            table.string( "originating_email", 320 ).nullable();

            table.string( "subject", 500 );
            table.string( "status", 20 ).default( "new" );
            table.string( "priority", 20 ).default( "normal" );
            table.string( "ticket_type", 20 ).default( "request" );
            table.string( "source", 20 ).default( "agent" );

            table.timestamp( "resolved_at" ).nullable();
            table.timestamp( "closed_at" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "organization_id" );
            table.index( "requester_contact_id" );
            table.index( "assigned_to_agent_id" );
            table.index( "status" );
            table.index( "priority" );
            table.index( "created_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "tickets" );
        queryExecute( "DROP SEQUENCE IF EXISTS tickets_ticket_number_seq" );
    }

}
