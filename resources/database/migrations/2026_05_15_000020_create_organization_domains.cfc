/**
 * Create organization_domains: maps an email domain to an Organization.
 *
 * When an inbound email arrives (channels, Phase 2) from an unknown
 * sender, the channel resolver looks up the sender's email domain in
 * this table. A hit places the resulting ticket in that organization;
 * a miss creates an accountless ticket.
 *
 * One domain maps to at most one organization. A provider can map
 * many domains to a single org (acme.com, acme.co.uk, acme.io).
 * is_verified gates whether the domain mapping was confirmed by the
 * client (Phase 2+); for Phase 1 the agent UI sets domains as verified.
 */
component {

    function up( schema, qb ){
        schema.create( "organization_domains", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.string( "domain", 253 ).unique();
            table.boolean( "is_verified" ).default( false );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "organization_domains" );
    }

}
