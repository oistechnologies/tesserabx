/**
 * Seed the in-app notification templates for Phase 5c-1.
 *
 * Idempotent: only inserts rows that do not yet exist for a given
 * (event_key, channel, recipient_type) tuple, so an operator that
 * has tweaked a template via the future admin UI keeps their edit.
 *
 * Placeholders the renderer substitutes:
 *   {{ticketNumber}}, {{subject}}, {{status}}, {{from}}, {{to}},
 *   {{ticketId}}, {{authorLabel}}
 */
component {

    function up( schema, qb ){
        upsert( arguments.qb, "ticket.created", "inapp", "agent",
                "New ticket ##{{ticketNumber}}: {{subject}}",
                "A new ticket landed in your queue.",
                "/agent/tickets/{{ticketId}}" );

        upsert( arguments.qb, "ticket.created", "inapp", "contact",
                "We received your request",
                "Your support request ##{{ticketNumber}} is on its way to an agent.",
                "/tickets/{{ticketId}}" );

        upsert( arguments.qb, "ticket.message_added", "inapp", "agent",
                "Customer replied on ##{{ticketNumber}}",
                "{{authorLabel}} added a message to ""{{subject}}"".",
                "/agent/tickets/{{ticketId}}" );

        upsert( arguments.qb, "ticket.message_added", "inapp", "contact",
                "Agent replied to your request ##{{ticketNumber}}",
                "An agent replied to ""{{subject}}"".",
                "/tickets/{{ticketId}}" );

        upsert( arguments.qb, "ticket.status_changed", "inapp", "agent",
                "Ticket ##{{ticketNumber}} moved to {{to}}",
                "Status changed from {{from}} to {{to}}.",
                "/agent/tickets/{{ticketId}}" );

        upsert( arguments.qb, "ticket.status_changed", "inapp", "contact",
                "Your ticket ##{{ticketNumber}} is now {{to}}",
                "We moved your ticket from {{from}} to {{to}}.",
                "/tickets/{{ticketId}}" );
    }

    function down( schema, qb ){
        queryExecute( "DELETE FROM notification_templates WHERE channel = 'inapp'" );
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
