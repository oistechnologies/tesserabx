/**
 * Create notification_preferences.
 *
 * One row per (recipient, event_key, channel) opt-out. Default is
 * opt-IN: the absence of a row means "deliver". An admin (or the
 * recipient themselves via a future UI) flips enabled=false to
 * silence a specific channel for an event without disabling the
 * whole event.
 *
 * Recipient_id is nullable so global defaults can live in this same
 * table later if we want them; today every row is per-recipient.
 *
 * Unique constraint mirrors the lookup: NotificationsService
 * checks `(recipient_type, recipient_id, event_key, channel)` and
 * sends iff there's no matching row with enabled=false.
 */
component {

    function up( schema, qb ){
        schema.create( "notification_preferences", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "recipient_type", 16 );
            table.string( "recipient_id", 36 );
            table.string( "event_key", 64 );
            table.string( "channel", 16 );
            table.boolean( "enabled" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "recipient_type", "recipient_id", "event_key", "channel" ] );
            table.index( [ "recipient_type", "recipient_id" ] );
        } );
    }

    function down( schema, qb ){
        schema.drop( "notification_preferences" );
    }

}
