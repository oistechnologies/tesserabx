/**
 * Seed email templates for ticket.status_changed.
 *
 * Phase 5c-2 wires email delivery through NotificationsService.
 * The other two ticket events (created / message_added) already
 * have email coverage in the channels module's OutboundEmailService;
 * adding email templates for them here would double-send. 5c-3 or a
 * later sweep consolidates onto a single path.
 *
 * Idempotent: only inserts a (event_key, channel, recipient_type)
 * tuple if it does not already exist.
 */
component {

    function up( schema, qb ){
        // Agent-facing email: useful for status flips an agent did
        // not personally trigger (automation, customer self-resolve).
        upsert( arguments.qb, "ticket.status_changed", "email", "agent",
                "Ticket ##{{ticketNumber}} moved to {{to}}",
                "Ticket ##{{ticketNumber}} (""{{subject}}"") changed status from {{from}} to {{to}}." & chr( 10 )
                & chr( 10 )
                & "Open it in TesseraBX: {{ticketId}}" );

        upsert( arguments.qb, "ticket.status_changed", "email", "contact",
                "Your ticket ##{{ticketNumber}} is now {{to}}",
                "Hi," & chr( 10 ) & chr( 10 )
                & "We updated your ticket ""{{subject}}"" from {{from}} to {{to}}." & chr( 10 )
                & chr( 10 )
                & "If you need anything else, just reply to this email and we will pick it back up." & chr( 10 )
                & chr( 10 )
                & "The support team" );
    }

    function down( schema, qb ){
        queryExecute(
            "DELETE FROM notification_templates
             WHERE  channel = 'email'
             AND    event_key = 'ticket.status_changed'"
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
