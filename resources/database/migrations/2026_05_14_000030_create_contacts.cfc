/**
 * Create contacts: client-side user accounts.
 *
 * Phase 0: minimum columns to authenticate. Phase 1 expands with merge
 * history, customer tiers, role assignments, etc. The organization_id
 * column and the tenant scope apply from this first migration; they
 * are NOT retrofitted.
 */
component {

    function up( schema, qb ){
        schema.create( "contacts", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.string( "office_id", 36 ).nullable().references( "id" ).onTable( "offices" ).onDelete( "SET NULL" );

            table.string( "email", 320 );
            table.string( "password_hash", 255 );
            table.string( "first_name", 100 ).nullable();
            table.string( "last_name", 100 ).nullable();
            table.boolean( "is_active" ).default( true );
            table.boolean( "is_organization_admin" ).default( false );
            table.timestamp( "last_login_at" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "organization_id", "email" ] );
            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "contacts" );
    }

}
