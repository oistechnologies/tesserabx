/**
 * Append an unsubscribe footer to existing email templates so
 * recipients can opt out from a single click. Idempotent: only
 * patches templates that do not already contain the {{unsubscribeUrl}}
 * placeholder (so an operator-edited body is left alone).
 *
 * The placeholder is resolved per-recipient at dispatch time with a
 * signed token; the endpoint at /unsubscribe verifies the signature
 * and flips the notification_preferences row.
 */
component {

    function up( schema, qb ){
        var footer = chr( 10 ) & chr( 10 )
                   & "----" & chr( 10 )
                   & "To stop receiving these emails: {{unsubscribeUrl}}";

        var rows = queryExecute(
            "SELECT id, body_template
             FROM   notification_templates
             WHERE  channel = 'email'"
        );
        for ( var i = 1; i <= rows.recordCount; i++ ) {
            var body = rows.body_template[ i ] ?: "";
            if ( findNoCase( "{{unsubscribeUrl}}", body ) ) continue;
            queryExecute(
                "UPDATE notification_templates
                 SET    body_template = :body,
                        updated_at    = NOW()
                 WHERE  id = :id",
                { id : rows.id[ i ], body : body & footer }
            );
        }
    }

    function down( schema, qb ){
        // No-op. We don't try to surgically strip the footer.
    }

}
