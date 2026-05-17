/**
 * Create agent_pending_email_changes: short-lived rows that hold
 * an in-flight email change request until the agent clicks the
 * verification link sent to the new address.
 *
 * token_hash is SHA-256 of the raw verification token. The raw token
 * only ever exists in the URL emailed to the new address; the server
 * recomputes the hash on confirmation and looks it up here. This
 * means a database leak cannot resurrect a stolen email change.
 *
 * Phase 4 sweeps expired/consumed rows on a scheduled task. Until
 * then the table stays small (per-agent, per-attempt) and we just
 * leave them.
 */
component {

    function up( schema, qb ){
        schema.create( "agent_pending_email_changes", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "agent_id", 36 ).references( "id" ).onTable( "agents" ).onDelete( "CASCADE" );
            table.string( "new_email", 320 );
            table.string( "token_hash", 100 );
            table.timestamp( "expires_at" );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "consumed_at" ).nullable();

            table.unique( "token_hash" );
            table.index( "agent_id" );
            table.index( "expires_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "agent_pending_email_changes" );
    }

}
