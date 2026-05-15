/**
 * Create notifications: the per-recipient delivery log.
 *
 * One row per (recipient, channel) delivery. For an in-app row the
 * record IS the notification an agent or contact sees in their bell
 * dropdown; for an email row it is the audit trail of a send (the
 * actual mail goes through cbmailservices and lands as separate
 * outbound_emails when Phase 5c-2 wires email templates through
 * here).
 *
 * status:
 *   - pending  : created, not yet delivered (queued)
 *   - sent     : delivery succeeded (inapp rows go straight to sent)
 *   - failed   : delivery error; the error_message column captures
 *                the reason
 *   - read     : inapp only; flips when the recipient opens it
 *
 * Not tenant-scoped at the row level. Recipient_type + recipient_id
 * disambiguate agent vs contact accounts.
 */
component {

    function up( schema, qb ){
        schema.create( "notifications", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "recipient_type", 16 );
            table.string( "recipient_id", 36 );
            table.string( "event_key", 64 );
            table.string( "channel", 16 );
            table.string( "title", 200 );
            table.text(   "body" );
            table.string( "link", 500 ).nullable();
            table.string( "status", 16 ).default( "pending" );
            table.text(   "error_message" ).nullable();
            table.string( "ticket_id", 36 ).nullable();
            table.string( "organization_id", 36 ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "sent_at" ).nullable();
            table.timestamp( "read_at" ).nullable();

            table.index( [ "recipient_type", "recipient_id", "status" ] );
            table.index( "event_key" );
            table.index( "created_at" );
            table.index( "ticket_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "notifications" );
    }

}
