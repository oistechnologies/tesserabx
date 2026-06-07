/**
 * Seed the email template for ticket.message_added, agent recipient.
 *
 * Recommendation R2 of the email audit: when a customer replies, the
 * assigned agent was alerted in-app only (the ticket.message_added
 * event had an inapp agent template but no email one), so an agent who
 * does not live in the dashboard could miss the reply. This adds the
 * email body for that case.
 *
 * Agent recipient ONLY, on purpose. The (ticket.message_added, email,
 * contact) tuple is intentionally left unseeded: an agent reply is
 * delivered to the requester by the channels module's
 * OutboundEmailService (Path A), and seeding a contact email here
 * would double-send. The interceptor targets the agent recipient only
 * when a CUSTOMER replies (an agent reply targets the contact
 * recipient), so this template fires exactly on inbound customer
 * replies and never on the agent's own reply.
 *
 * Per-recipient opt-out via notification_preferences still applies, so
 * an agent who finds this noisy can silence (ticket.message_added,
 * email) without affecting the in-app bell.
 *
 * Idempotent: skips the tuple if it already exists.
 */
component {

    function up( schema, qb ){
        upsert( arguments.qb, "ticket.message_added", "email", "agent",
                "New reply on ticket ##{{ticketNumber}}",
                "{{authorLabel}} replied to ""{{subject}}""." & chr( 10 )
                & chr( 10 )
                & "Open it: {{appBaseUrl}}/agent/tickets/{{ticketId}}" );
    }

    function down( schema, qb ){
        queryExecute(
            "DELETE FROM notification_templates
             WHERE  event_key      = 'ticket.message_added'
             AND    channel        = 'email'
             AND    recipient_type = 'agent'"
        );
    }

    private void function upsert(
        required any qb,
        required string eventKey,
        required string channel,
        required string recipientType,
        required string title,
        required string body
    ){
        var existing = queryExecute(
            "SELECT id FROM notification_templates
             WHERE  event_key = :ek AND channel = :ch AND recipient_type = :rt",
            { ek : arguments.eventKey, ch : arguments.channel, rt : arguments.recipientType }
        );
        if ( existing.recordCount ) return;
        queryExecute(
            "INSERT INTO notification_templates
                ( id, event_key, channel, recipient_type, title_template, body_template, is_active )
             VALUES
                ( :id, :ek, :ch, :rt, :title, :body, TRUE )",
            {
                id    : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
                ek    : arguments.eventKey,
                ch    : arguments.channel,
                rt    : arguments.recipientType,
                title : arguments.title,
                body  : arguments.body
            }
        );
    }

}
