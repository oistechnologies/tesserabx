/**
 * Expand offices into full location records.
 *
 * An office was just a named grouping inside an organization. To
 * support "multiple office locations" it now carries a mailing
 * address, a phone, a time zone, and an is_primary flag marking the
 * organization's headquarters / default location.
 *
 * All columns nullable or defaulted so existing rows migrate cleanly.
 */
component {

    function up( schema, qb ){
        schema.alter( "offices", function( table ){
            table.addColumn( table.string( "address_line1", 255 ).nullable() );
            table.addColumn( table.string( "address_line2", 255 ).nullable() );
            table.addColumn( table.string( "city", 120 ).nullable() );
            table.addColumn( table.string( "region", 120 ).nullable() );
            table.addColumn( table.string( "postal_code", 20 ).nullable() );
            table.addColumn( table.string( "country", 2 ).nullable() );
            table.addColumn( table.string( "phone", 50 ).nullable() );
            table.addColumn( table.string( "timezone", 64 ).nullable() );
            table.addColumn( table.boolean( "is_primary" ).default( false ) );
        } );
    }

    function down( schema, qb ){
        schema.alter( "offices", function( table ){
            table.dropColumn( "address_line1" );
            table.dropColumn( "address_line2" );
            table.dropColumn( "city" );
            table.dropColumn( "region" );
            table.dropColumn( "postal_code" );
            table.dropColumn( "country" );
            table.dropColumn( "phone" );
            table.dropColumn( "timezone" );
            table.dropColumn( "is_primary" );
        } );
    }

}
