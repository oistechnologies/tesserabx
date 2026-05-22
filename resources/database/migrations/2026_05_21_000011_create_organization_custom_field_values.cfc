/**
 * Create organization_custom_field_values.
 *
 * Phase 9 of the extensibility plan generalizes custom fields beyond
 * tickets. Same typed-column layout as ticket_custom_field_values;
 * the entity column is organization_id, foreign-keyed to organizations.
 *
 * Tenant scope is the organization itself; no separate tenancy column.
 */
component {

    function up( schema, qb ){
        schema.create( "organization_custom_field_values", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.string( "definition_id", 36 ).references( "id" ).onTable( "custom_field_definitions" ).onDelete( "CASCADE" );
            table.text( "value_text" ).nullable();
            table.decimal( "value_number", 20, 6 ).nullable();
            table.timestamp( "value_date" ).nullable();
            table.boolean( "value_boolean" ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "organization_id", "definition_id" ] );
            table.index( "organization_id" );
            table.index( "definition_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "organization_custom_field_values" );
    }

}
