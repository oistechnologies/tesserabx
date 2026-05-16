/**
 * Create agent_roles: the provider-side role assignment table.
 *
 * Parallels contact_roles but for Agent accounts. Each row assigns
 * one role_key to one agent. The role set is extensible without
 * schema changes; Phase 5d defines "agent-admin" and "agent-supervisor",
 * later phases can add narrower keys.
 *
 * Agents are NOT tenant-scoped (they see across all organizations),
 * so this table also is not tenant-scoped.
 */
component {

    function up( schema, qb ){
        schema.create( "agent_roles", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "agent_id", 36 ).references( "id" ).onTable( "agents" ).onDelete( "CASCADE" );
            table.string( "role_key", 100 );
            table.string( "granted_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            table.timestamp( "granted_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "agent_id", "role_key" ] );
            table.index( "agent_id" );
            table.index( "role_key" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "agent_roles" );
    }

}
