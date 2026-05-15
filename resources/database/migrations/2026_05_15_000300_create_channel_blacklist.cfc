/**
 * Create channel_blacklist: senders and domains the channels module
 * drops on inbound intake.
 *
 * entry_type is either "email" (full address) or "domain" (host
 * portion only, e.g. "spam.example.com"). The value column stores
 * the lowercased address or domain. is_active lets an agent
 * temporarily disable a rule without deleting it.
 *
 * Distinct from the audit log: this is a config table the channels
 * service queries on every inbound message. Matches do not produce
 * tickets; matches DO produce an audit_events row for traceability.
 */
component {

    function up( schema, qb ){
        schema.create( "channel_blacklist", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "entry_type", 20 );
            table.string( "value", 320 );
            table.string( "reason", 500 ).nullable();
            table.boolean( "is_active" ).default( true );
            table.string( "added_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "entry_type", "value" ] );
            table.index( "entry_type" );
            table.index( "value" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "channel_blacklist" );
    }

}
