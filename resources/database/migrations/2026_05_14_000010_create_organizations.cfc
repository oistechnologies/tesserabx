/**
 * Create organizations: the tenant boundary.
 *
 * Phase 0 ships the minimal columns needed for tenancy and login flow.
 * Phase 1 expands with tier, domain mappings, custom fields, etc.
 */
component {

    function up( schema, qb ){
        schema.create( "organizations", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 255 );
            table.string( "slug", 100 ).unique();
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "organizations" );
    }

}
