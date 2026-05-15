/**
 * Create inbound_emails: append-only log of every inbound message
 * channels has processed.
 *
 * Records what arrived, what was decided (created a ticket, appended
 * a message, dropped by blacklist, dropped by loop guard), and which
 * resulting ticket if any. Lets an operator trace why a particular
 * email did or did not produce a ticket without re-reading raw IMAP
 * traffic.
 *
 * message_id is the RFC 5322 Message-ID header so duplicate IMAP
 * polls of the same mailbox don't re-process the same message.
 */
component {

    function up( schema, qb ){
        schema.create( "inbound_emails", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "message_id", 998 ).nullable();
            table.string( "sender_email", 320 );
            table.string( "subject", 998 ).nullable();
            table.string( "in_reply_to", 998 ).nullable();
            table.text( "references_chain" ).nullable();
            table.string( "outcome", 30 );
            table.string( "ticket_id", 36 ).nullable().references( "id" ).onTable( "tickets" ).onDelete( "SET NULL" );
            table.text( "notes" ).nullable();
            table.timestamp( "received_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "message_id" );
            table.index( "sender_email" );
            table.index( "outcome" );
            table.index( "received_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "inbound_emails" );
    }

}
