/**
 * Create custom_field_definitions.
 *
 * The admin-managed catalog of extra fields that attach to a
 * domain entity. Phase 5e-2 ships entity_type='ticket'; later
 * phases extend the same table to 'contact' and (potentially)
 * 'organization'.
 *
 * Definitions live in the tickets module per the CLAUDE.md
 * ownership rule ("tickets owns custom-field entities"). The
 * admin UI manages them through tickets' service layer.
 *
 * field_type is one of: text | textarea | number | date | select
 * | boolean. The options column holds the choice list for select
 * fields as a JSONB array; ignored for other types.
 *
 * Not tenant-scoped: the schema applies across all organizations
 * the provider's agents touch. (Per-organization custom fields,
 * if they ever arrive, would carry organization_id here.)
 */
component {

    function up( schema, qb ){
        schema.create( "custom_field_definitions", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "entity_type", 50 );
            table.string( "key", 100 );
            table.string( "label", 200 );
            table.string( "field_type", 30 );
            table.text( "options" ).nullable();
            table.text( "help_text" ).nullable();
            table.boolean( "is_required" ).default( false );
            table.boolean( "is_active" ).default( true );
            table.integer( "sort_order" ).default( 0 );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "entity_type", "key" ] );
            table.index( "entity_type" );
            table.index( "is_active" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "custom_field_definitions" );
    }

}
