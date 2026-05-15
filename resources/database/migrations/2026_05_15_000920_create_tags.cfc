/**
 * Create tags + ticket_tags.
 *
 * Tags are global (one row per name) and many-to-many with tickets
 * via ticket_tags. Provider-side configuration so agents and the
 * triage service share one vocabulary; phase 5's admin UI can rename
 * or merge tags without touching tickets.
 *
 * Slug is the canonicalized name (lower-case, hyphenated) used for
 * dedup and URL safety. The unique index on slug ensures that the
 * AI triage service can upsert with INSERT ... ON CONFLICT DO NOTHING.
 */
component {

    function up( schema, qb ){
        schema.create( "tags", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 80 );
            table.string( "slug", 80 ).unique();
            table.string( "color", 24 ).default( "secondary" );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
        } );

        schema.create( "ticket_tags", function( table ){
            table.string( "ticket_id", 36 );
            table.string( "tag_id", 36 );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.primaryKey( [ "ticket_id", "tag_id" ] );
            table.index( "tag_id" );

            table.foreignKey( "ticket_id" ).references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );
            table.foreignKey( "tag_id" ).references( "id" ).onTable( "tags" ).onDelete( "CASCADE" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "ticket_tags" );
        schema.drop( "tags" );
    }

}
