/**
 * Add message_id to ticket_messages.
 *
 * Stores the RFC 5322 Message-ID for both inbound and outbound
 * messages. For inbound the channel processor copies it from the
 * email headers; for outbound the channels module generates a new
 * one when sending. Lets the inbound pipeline match a new inbound
 * email's In-Reply-To against any prior message in the thread,
 * whether that prior message was an inbound or an outbound reply.
 */
component {

    function up( schema, qb ){
        schema.alter( "ticket_messages", function( table ){
            table.addColumn( table.string( "message_id", 998 ).nullable() );
        } );
        // Looked up case-sensitively by In-Reply-To matching.
        queryExecute( "CREATE INDEX idx_ticket_messages_message_id ON ticket_messages ( message_id )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_ticket_messages_message_id" );
        schema.alter( "ticket_messages", function( table ){
            table.dropColumn( "message_id" );
        } );
    }

}
