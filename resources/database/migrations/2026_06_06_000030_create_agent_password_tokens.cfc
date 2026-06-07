/**
 * Create agent_password_tokens: one-time tokens for the agent
 * self-service password reset (email audit R3).
 *
 * Mirrors contact_password_tokens but targets the agents table.
 * AgentService.requestPasswordReset writes a row holding the SHA-256
 * hash of a single-use token (the raw token is emailed, never stored).
 * Following the /agent/reset-password?token= link verifies the hash,
 * checks it is neither expired nor consumed, sets the chosen password,
 * and stamps consumed_at. MFA enforcement on the far side of login is
 * unchanged; this only resets the password factor.
 *
 * Agents have no invite flow (they are admin-provisioned), so the
 * purpose column defaults to "reset".
 */
component {

    function up( schema, qb ){
        schema.create( "agent_password_tokens", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "agent_id", 36 ).references( "id" ).onTable( "agents" ).onDelete( "CASCADE" );
            table.string( "token_hash", 64 );
            table.string( "purpose", 30 ).default( "reset" );
            table.timestamp( "expires_at" );
            table.timestamp( "consumed_at" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "agent_id" );
            table.index( "token_hash" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "agent_password_tokens" );
    }

}
