/**
 * Create notification_bounces: the audit trail of hard / soft mail
 * bounces tied back to the notification that triggered the send.
 *
 * Phase 5c-3 ships the data model and the recordBounce() service
 * method. Wiring this up to a live mail-provider webhook (SES SNS,
 * Postmark, etc.) is operator work and varies by provider; the
 * stable shape lets us add provider integrations later without
 * another migration.
 */
component {

    function up( schema, qb ){
        schema.create( "notification_bounces", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "notification_id", 36 ).nullable();
            table.string( "recipient_email", 320 );
            table.string( "kind", 16 ); // "hard" | "soft"
            table.text(   "reason" ).nullable();
            table.timestamp( "received_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "notification_id" );
            table.index( "recipient_email" );
            table.index( "received_at" );

            table.foreignKey( "notification_id" )
                 .references( "id" ).onTable( "notifications" )
                 .onDelete( "SET NULL" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "notification_bounces" );
    }

}
