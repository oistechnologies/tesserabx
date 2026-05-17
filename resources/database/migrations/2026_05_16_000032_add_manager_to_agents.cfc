/**
 * Add manager_agent_id self-referential foreign key to agents.
 *
 * Lets an agent point to another agent as their manager. ON DELETE
 * SET NULL so deactivating or deleting a manager doesn't cascade and
 * orphan the reports row; it just clears the link.
 *
 * Self-referential FK isolated in its own migration so a clean
 * rollback only undoes this one piece.
 */
component {

    function up( schema, qb ){
        schema.alter( "agents", function( table ){
            table.addColumn( table.string( "manager_agent_id", 36 ).nullable() );
        } );
        queryExecute(
            "ALTER TABLE agents
             ADD CONSTRAINT fk_agents_manager_agent_id
             FOREIGN KEY ( manager_agent_id ) REFERENCES agents ( id )
             ON DELETE SET NULL"
        );
        queryExecute( "CREATE INDEX idx_agents_manager_agent_id ON agents ( manager_agent_id )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_agents_manager_agent_id" );
        queryExecute( "ALTER TABLE agents DROP CONSTRAINT IF EXISTS fk_agents_manager_agent_id" );
        schema.alter( "agents", function( table ){
            table.dropColumn( "manager_agent_id" );
        } );
    }

}
