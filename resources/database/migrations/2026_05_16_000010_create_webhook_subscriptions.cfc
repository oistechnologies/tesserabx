/**
 * Create webhook_subscriptions + webhook_deliveries.
 *
 * Outbound webhook dispatch for the api module. Other systems
 * register a (name, target_url, event_keys[], secret) and our
 * dispatcher POSTs a signed JSON payload to that URL whenever a
 * matching event fires.
 *
 * webhook_deliveries records every attempted POST so an admin
 * can review recent deliveries, see failures, and replay.
 *
 * Not tenant-scoped: subscriptions are provider-side integrations
 * (Zapier, internal services, etc.). Phase 6 ships the model; a
 * per-organization subscription surface is deferred.
 */
component {

    function up( schema, qb ){
        schema.create( "webhook_subscriptions", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.string( "target_url", 1000 );
            // Comma-separated event keys (e.g. "ticket.created,ticket.status_changed").
            // A magic value of "*" subscribes to every event the dispatcher emits.
            table.string( "event_keys", 500 );
            // HMAC-SHA256 signing secret. We include this in the
            // X-TesseraBX-Signature header so receivers can verify
            // payload authenticity.
            table.string( "secret", 200 );
            table.boolean( "is_active" ).default( true );
            table.string( "created_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "is_active" );
        } );

        schema.create( "webhook_deliveries", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "subscription_id", 36 ).references( "id" ).onTable( "webhook_subscriptions" ).onDelete( "CASCADE" );
            table.string( "event_key", 100 );
            table.string( "target_url", 1000 );
            table.text( "payload_json" );
            table.string( "status", 20 ).default( "pending" );
            table.integer( "status_code" ).nullable();
            table.text( "response_body" ).nullable();
            table.text( "error_message" ).nullable();
            table.integer( "attempt_count" ).default( 0 );
            table.timestamp( "scheduled_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "sent_at" ).nullable();
            table.timestamp( "completed_at" ).nullable();

            table.index( "subscription_id" );
            table.index( "status" );
            table.index( "event_key" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "webhook_deliveries" );
        schema.drop( "webhook_subscriptions" );
    }

}
