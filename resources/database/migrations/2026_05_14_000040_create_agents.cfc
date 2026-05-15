/**
 * Create agents: provider-side technician accounts.
 *
 * Agents are NOT tenant-scoped: they see across organizations subject
 * to RBAC. No organization_id column.
 *
 * Phase 6 adds MFA columns (TOTP secret, recovery codes).
 */
component {

    function up( schema, qb ){
        schema.create( "agents", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "email", 320 ).unique();
            table.string( "password_hash", 255 );
            table.string( "first_name", 100 ).nullable();
            table.string( "last_name", 100 ).nullable();
            table.boolean( "is_active" ).default( true );
            table.boolean( "is_admin" ).default( false );
            table.timestamp( "last_login_at" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "agents" );
    }

}
