/**
 * Example Sync entity-extension table.
 *
 * Demonstrates Phase 9.2's convention: a per-add-on extension table
 * attached to a core entity (here: tickets). Surrogate id PK matches
 * the qb migration shape used elsewhere; the unique index on
 * ticket_id enforces one row per ticket.
 *
 * This file is the canonical source. The Migrate task
 * (tasks/Migrate.cfc, follow-up A7) discovers add-on migrations
 * under sample-addons/, modules_app/, and TesseraBX-marked modules/,
 * then stages each into resources/database/migrations/ with an
 * `_addon_` prefix so the standard cfmigrations runner picks them
 * up. Staged copies are gitignored; only this source is
 * version-controlled.
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
