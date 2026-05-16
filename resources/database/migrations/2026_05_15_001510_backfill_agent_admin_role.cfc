/**
 * Backfill: every agent currently flagged is_admin=TRUE gets an
 * agent_roles row with role_key='agent-admin'.
 *
 * The is_admin column stays as a back-compat hint for existing
 * specs and seeders; getRoles() reads from agent_roles first and
 * falls back to is_admin only when no rows exist for the agent.
 */
component {

    function up( schema, qb ){
        var rows = queryExecute(
            "SELECT id FROM agents WHERE is_admin = TRUE"
        );
        for ( var i = 1; i <= rows.recordCount; i++ ) {
            queryExecute(
                "INSERT INTO agent_roles ( id, agent_id, role_key, granted_at )
                 VALUES ( :id, :aid, 'agent-admin', NOW() )
                 ON CONFLICT ( agent_id, role_key ) DO NOTHING",
                {
                    id  : createUUID(),
                    aid : rows.id[ i ]
                }
            );
        }
    }

    function down( schema, qb ){
        queryExecute(
            "DELETE FROM agent_roles WHERE role_key = 'agent-admin'"
        );
    }

}
