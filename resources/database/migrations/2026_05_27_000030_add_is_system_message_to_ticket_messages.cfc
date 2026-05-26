/**
 * Add is_system_message to ticket_messages.
 *
 * Distinguishes system-authored records (auto-acks, future canned
 * "ticket was reassigned" stubs, etc.) from real customer or agent
 * messages. The notifications fan-out short-circuits on this flag
 * so the auto-ack's own TicketMessage does not generate a second
 * "ticket.message_added" notification on top of the ack the
 * channel adapter already delivered.
 */
component {

    function up( schema, qb ){
        schema.alter( "ticket_messages", function( table ){
            table.addColumn( table.boolean( "is_system_message" ).default( false ) );
        } );
    }

    function down( schema, qb ){
        schema.alter( "ticket_messages", function( table ){
            table.dropColumn( "is_system_message" );
        } );
    }

}
