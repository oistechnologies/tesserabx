/**
 * Example Sync entity-extension table.
 *
 * Demonstrates Phase 9.2's convention: a per-add-on extension table
 * attached to a core entity (here: tickets). Surrogate id PK matches
 * the qb migration shape used elsewhere; the unique index on
 * ticket_id enforces one row per ticket.
 *
 * In a real add-on the migration would ship with the add-on. For this
 * sample it lives in the core migrations folder because cfmigrations
 * only scans resources/database/migrations/. A near-term improvement
 * is to let cfmigrations follow per-add-on migrations folders too.
 *
 * The canonical copy of this file lives at
 *   sample-addons/example-sync/migrations/<timestamp>_create_tickets_example_sync.cfc
 * and a real add-on would carry it there. This duplicate exists only
 * because of the cfmigrations scanning limit above.
 */
component {

    function up( schema, qb ){
        schema.create( "tickets_example_sync", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "ticket_id", 36 ).references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );
            table.string( "organization_id", 36 ).nullable().references( "id" ).onTable( "organizations" );
            table.string( "external_issue_key", 100 ).nullable();
            table.string( "external_project_key", 100 ).nullable();
            table.timestamp( "linked_at" ).nullable();
            table.timestamp( "last_synced_at" ).nullable();
            table.text( "snapshot" ).nullable();

            table.unique( "ticket_id" );
            table.index( "external_issue_key" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "tickets_example_sync" );
    }

}
