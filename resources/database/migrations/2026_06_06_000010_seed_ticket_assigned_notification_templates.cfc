/**
 * Seed in-app + email templates for ticket.assigned.
 *
 * Recommendation R1 of the email audit: the onTicketAssigned event
 * was announced but had no listener and no template, so a newly
 * assigned agent was never told. TicketEventsInterceptor.onTicketAssigned
 * now dispatches ticket.assigned to the new assignee; these rows give
 * that dispatch an in-app card and an email body.
 *
 * Agent recipient only. A contact has no need to know which internal
 * agent picked up their ticket. Self-assignment is filtered in the
 * interceptor, so these only fire when someone assigns the ticket to
 * a different agent.
 *
 * Idempotent: only inserts a (event_key, channel, recipient_type)
 * tuple if it does not already exist, so an operator edit via the
 * admin UI survives a re-run.
 */
component {

    function up( schema, qb ){
        upsert( arguments.qb, "ticket.assigned", "inapp", "agent",
                "Ticket ##{{ticketNumber}} assigned to you",
                "You were assigned ""{{subject}}"".",
                "/agent/tickets/{{ticketId}}" );

        upsert( arguments.qb, "ticket.assigned", "email", "agent",
                "Ticket ##{{ticketNumber}} assigned to you",
                "Ticket ##{{ticketNumber}} (""{{subject}}"") has been assigned to you." & chr( 10 )
                & chr( 10 )
                & "Open it: {{appBaseUrl}}/agent/tickets/{{ticketId}}",
                "/agent/tickets/{{ticketId}}" );
    }

    function down( schema, qb ){
        queryExecute(
            "DELETE FROM notification_templates
             WHERE  event_key = 'ticket.assigned'"
        );
    }

    private void function upsert(
        required any qb,
        required string eventKey,
        required string channel,
        required string recipientType,
        required string title,
        required string body,
        required string link
    ){
        var existing = queryExecute(
            "SELECT id FROM notification_templates
             WHERE  event_key = :ek AND channel = :ch AND recipient_type = :rt",
            { ek : arguments.eventKey, ch : arguments.channel, rt : arguments.recipientType }
        );
        if ( existing.recordCount ) return;
        queryExecute(
            "INSERT INTO notification_templates
                ( id, event_key, channel, recipient_type, title_template, body_template, link_template, is_active )
             VALUES
                ( :id, :ek, :ch, :rt, :title, :body, :link, TRUE )",
            {
                id    : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
                ek    : arguments.eventKey,
                ch    : arguments.channel,
                rt    : arguments.recipientType,
                title : arguments.title,
                body  : arguments.body,
                link  : arguments.link
            }
        );
    }

}
