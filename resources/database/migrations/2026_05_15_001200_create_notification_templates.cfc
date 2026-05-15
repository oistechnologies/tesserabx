/**
 * Create notification_templates.
 *
 * One row per (event_key, channel) pair. The notifications service
 * looks the row up at dispatch time and renders title/body/link with
 * a {{placeholder}} substitution against the event's context struct.
 *
 * Channel is `inapp`, `email`, or `slack`. Phase 5c-1 ships in-app;
 * email + slack land in later sub-phases without touching the
 * schema.
 *
 * recipient_type pins which side the template targets. Some events
 * (ticket.message_added) fan to both an agent and a contact with
 * different wording; we model that as two rows.
 */
component {

    function up( schema, qb ){
        schema.create( "notification_templates", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "event_key", 64 );
            table.string( "channel", 16 );
            table.string( "recipient_type", 16 );
            table.string( "title_template", 200 );
            table.text(   "body_template" );
            table.string( "link_template", 500 ).nullable();
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "event_key", "channel", "recipient_type" ] );
            table.index( "event_key" );
            table.index( "is_active" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "notification_templates" );
    }

}
