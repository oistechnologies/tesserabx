/**
 * Add tier column to organizations.
 *
 * Customer tier is per-organization (a single provider may serve a
 * Bronze client and a Platinum client; tier never lives on Contact).
 * Stored as a free-form string so the provider can rename or extend
 * tiers without a schema migration; the value comes from a known list
 * defined in the contacts service.
 */
component {

    function up( schema, qb ){
        schema.alter( "organizations", function( table ){
            table.addColumn( table.string( "tier", 50 ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "organizations", function( table ){
            table.dropColumn( "tier" );
        } );
    }

}
