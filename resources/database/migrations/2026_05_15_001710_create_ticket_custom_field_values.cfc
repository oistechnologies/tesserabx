/**
 * Create ticket_custom_field_values.
 *
 * One row per (ticket, definition). Typed columns (value_text,
 * value_number, value_date, value_boolean) let reporting query
 * and filter without parsing JSON. Only the column matching the
 * definition's field_type is populated; the rest stay NULL.
 *
 * Tenant scope follows the parent ticket FK; the ticket itself
 * carries organization_id. Same pattern as ticket_messages.
 */
component {

    function up( schema, qb ){
        schema.create( "ticket_custom_field_values", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "ticket_id", 36 ).references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );
            table.string( "definition_id", 36 ).references( "id" ).onTable( "custom_field_definitions" ).onDelete( "CASCADE" );
            table.text( "value_text" ).nullable();
            table.decimal( "value_number", 20, 6 ).nullable();
            table.timestamp( "value_date" ).nullable();
            table.boolean( "value_boolean" ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "ticket_id", "definition_id" ] );
            table.index( "ticket_id" );
            table.index( "definition_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "ticket_custom_field_values" );
    }

}
