/**
 * Create contact_roles: the client-side role assignment table.
 *
 * Each row assigns one role to one Contact. The role_key is a string
 * so the role set is extensible without schema changes. Phase 1
 * defines "organization-admin" as the first role; later phases add
 * more (for example "billing-contact", "watcher-only").
 *
 * Replaces the is_organization_admin boolean on contacts, which the
 * next migration backfills and then drops.
 */
component {

    function up( schema, qb ){
        schema.create( "contact_roles", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "contact_id", 36 ).references( "id" ).onTable( "contacts" ).onDelete( "CASCADE" );
            table.string( "role_key", 100 );
            table.string( "granted_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            table.timestamp( "granted_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "contact_id", "role_key" ] );
            table.index( "contact_id" );
            table.index( "role_key" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "contact_roles" );
    }

}
