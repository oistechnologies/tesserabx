/**
 * Create contact_password_tokens: one-time set-password tokens for the
 * Organization-Admin member invite flow.
 *
 * When an org admin invites a new member, ContactInviteService
 * provisions the Contact with a random password and writes a row here
 * holding the SHA-256 hash of a single-use token (the raw token is
 * emailed, never stored), mirroring the PendingTicketsService pattern.
 * Following the /set-password?token= link verifies the hash, checks it
 * is neither expired nor consumed, sets the chosen password, and stamps
 * consumed_at. The same table backs a future self-service password
 * reset.
 */
component {

    function up( schema, qb ){
        schema.create( "contact_password_tokens", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "contact_id", 36 ).references( "id" ).onTable( "contacts" ).onDelete( "CASCADE" );
            table.string( "token_hash", 64 );
            table.string( "purpose", 30 ).default( "invite" );
            table.timestamp( "expires_at" );
            table.timestamp( "consumed_at" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "contact_id" );
            table.index( "token_hash" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "contact_password_tokens" );
    }

}
