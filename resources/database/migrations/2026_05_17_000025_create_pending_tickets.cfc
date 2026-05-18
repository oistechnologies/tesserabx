/**
 * pending_tickets: short-lived rows for guest contact-form
 * submissions awaiting email verification.
 *
 * When an unauthenticated visitor submits the public contact form
 * we land the payload here instead of creating a Ticket. A
 * verification email goes to the sender's address; clicking the
 * link consumes the row and materializes a real (accountless)
 * Ticket through TicketsService. Unverified rows expire and are
 * swept by the retention scheduler.
 *
 * Columns:
 *  - token_hash: SHA-256 of the raw token mailed to the visitor.
 *    The raw token never lands in the database — only the hash —
 *    so a DB read does not leak active verification URLs.
 *  - sender_email / sender_name: who submitted. sender_name is
 *    optional; the contact form allows it to be blank.
 *  - subject / body / source: the payload we'll hand to
 *    TicketsService.createAccountlessTicket once verified.
 *  - expires_at: NOW() + PENDING_TICKET_TTL_HOURS at insert time.
 *  - consumed_at: stamped on successful confirm. Both replay
 *    attempts and expiry filter against this column.
 *
 * No tenant scope: pending rows are pre-tenancy by design; the
 * resulting ticket is accountless until an agent promotes the
 * sender into a Contact (the same path as accountless email
 * tickets).
 */
component {

    function up( schema, qb ){
        schema.create( "pending_tickets", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "token_hash", 64 ).unique();
            table.string( "sender_email", 255 );
            table.string( "sender_name", 255 ).nullable();
            table.text( "subject" );
            table.text( "body" );
            table.string( "source", 50 ).default( "contact-form" );
            table.timestamp( "created_at" ).default( "NOW()" );
            table.timestamp( "expires_at" );
            table.timestamp( "consumed_at" ).nullable();
        } );
        queryExecute( "CREATE INDEX idx_pending_tickets_expires_at ON pending_tickets ( expires_at )" );
        queryExecute( "CREATE INDEX idx_pending_tickets_sender_email ON pending_tickets ( sender_email )" );
    }

    function down( schema, qb ){
        schema.drop( "pending_tickets" );
    }

}
