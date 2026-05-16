/**
 * Seed Slack templates for ticket.status_changed (agent side only).
 *
 * The Slack channel posts to a single shared incoming webhook
 * (SLACK_WEBHOOK_URL). Contacts are not Slack-side recipients in
 * this model; only agent rows are seeded so the dispatch loop has
 * something to fan out.
 *
 * The body_template uses Slack's plain-text formatting so the same
 * payload also works with a Teams Slack-compatible webhook.
 */
component {

    function up( schema, qb ){
        var existing = queryExecute(
            "SELECT id FROM notification_templates
             WHERE  event_key = 'ticket.status_changed'
             AND    channel   = 'slack'
             AND    recipient_type = 'agent'"
        );
        if ( existing.recordCount ) return;

        queryExecute(
            "INSERT INTO notification_templates
                ( id, event_key, channel, recipient_type, title_template, body_template, link_template, is_active )
             VALUES
                ( :id, 'ticket.status_changed', 'slack', 'agent',
                  'Ticket ##{{ticketNumber}} -> {{to}}',
                  ':ticket: *##{{ticketNumber}}* ""{{subject}}"" moved from `{{from}}` to `{{to}}`',
                  '{{appBaseUrl}}/agent/tickets/{{ticketId}}',
                  TRUE )",
            { id : createObject( "java", "java.util.UUID" ).randomUUID().toString() }
        );
    }

    function down( schema, qb ){
        queryExecute(
            "DELETE FROM notification_templates
             WHERE  channel = 'slack'
             AND    event_key = 'ticket.status_changed'"
        );
    }

}
