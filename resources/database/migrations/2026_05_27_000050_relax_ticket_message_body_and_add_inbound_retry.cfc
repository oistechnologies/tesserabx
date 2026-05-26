/**
 * Two defensive-shape changes triggered by the bx-mail lazy
 * getContent() bug on inbound multipart emails with attachments.
 *
 * 1. ticket_messages.body: drop NOT NULL.
 *    The processor coerces empty bodies to "" but the bx-mail jar
 *    has been observed handing back a Java null on the first
 *    multipart fetch, slipping past every BoxLang-level coalesce
 *    and falling through to a NULL-violating INSERT. Allowing the
 *    column to hold NULL means a transient empty body no longer
 *    orphans the parent ticket and tickets are recoverable through
 *    retry rather than through manual DB cleanup.
 *
 * 2. inbound_emails: add retry_count + last_attempted_at.
 *    The dedup check in InboundEmailProcessor used to treat any
 *    prior row as terminal. Once an "error" outcome was recorded,
 *    the IMAP message was abandoned. These columns drive a bounded
 *    retry loop: an "error" row is retried until retry_count hits
 *    INBOUND_EMAIL_MAX_RETRIES (defaults to 3) and only then
 *    becomes terminal.
 */
component {

    function up( schema, qb ){
        // 1. Allow body to be null. qb's alter / modifyColumn shape:
        //    re-declare the column with nullable() and modifyColumn.
        schema.alter( "ticket_messages", function( table ){
            table.modifyColumn( "body", table.text( "body" ).nullable() );
        } );

        // 2. Retry tracking columns on inbound_emails.
        schema.alter( "inbound_emails", function( table ){
            table.addColumn( table.integer( "retry_count" ).default( 0 ) );
            table.addColumn( table.timestamp( "last_attempted_at" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "inbound_emails", function( table ){
            table.dropColumn( "last_attempted_at" );
            table.dropColumn( "retry_count" );
        } );
        // Re-imposing NOT NULL on body would fail on any historical
        // null rows; intentionally leave nullable on down.
    }

}
