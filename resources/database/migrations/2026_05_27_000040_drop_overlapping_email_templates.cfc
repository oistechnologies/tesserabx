/**
 * Drop the (email, contact) notification_templates rows for
 * ticket.created and ticket.message_added.
 *
 * The channel adapter (OutboundEmailService.sendAutoAcknowledgement
 * and sendAgentReply) already delivers those two events to the
 * requester contact on every email-able ticket. The original DB
 * seed migration deliberately skipped these tuples for that
 * reason; this migration is the defensive cleanup in case any
 * environment manually inserted or re-seeded them. Down restores
 * neither, since the registry seeds for these tuples were
 * removed alongside this change.
 *
 * Idempotent: a missing row is fine.
 */
component {

    function up( schema, qb ){
        queryExecute(
            "DELETE FROM notification_templates
              WHERE channel        = 'email'
                AND recipient_type = 'contact'
                AND event_key IN ( 'ticket.created', 'ticket.message_added' )"
        );
    }

    function down( schema, qb ){
        // Intentional no-op. The two tuples are owned by the
        // channels module's OutboundEmailService and should not
        // exist in notification_templates regardless of direction.
    }

}
