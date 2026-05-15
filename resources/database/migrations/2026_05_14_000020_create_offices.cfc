/**
 * Create offices: optional grouping within an organization.
 */
component {

    function up( schema, qb ){
        schema.create( "offices", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.string( "name", 255 );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "offices" );
    }

}
