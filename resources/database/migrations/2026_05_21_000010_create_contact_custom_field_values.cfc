/**
 * Create contact_custom_field_values.
 *
 * Phase 9 of the extensibility plan generalizes custom fields beyond
 * tickets. Same typed-column layout as ticket_custom_field_values;
 * the entity column is contact_id, foreign-keyed to contacts.
 *
 * Tenant scope follows the parent contact FK (contact rows carry
 * organization_id). No tenancy column on this table.
 */
component {

    function up( schema, qb ){
        schema.create( "contact_custom_field_values", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "contact_id", 36 ).references( "id" ).onTable( "contacts" ).onDelete( "CASCADE" );
            table.string( "definition_id", 36 ).references( "id" ).onTable( "custom_field_definitions" ).onDelete( "CASCADE" );
            table.text( "value_text" ).nullable();
            table.decimal( "value_number", 20, 6 ).nullable();
            table.timestamp( "value_date" ).nullable();
            table.boolean( "value_boolean" ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "contact_id", "definition_id" ] );
            table.index( "contact_id" );
            table.index( "definition_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "contact_custom_field_values" );
    }

}
