/**
 * Expand contacts with support-CRM attributes.
 *
 * Phone numbers, job title, time zone, and locale let agents reach and
 * address a contact correctly; is_vip flags priority handling at
 * triage; notes carries agent-only context. source records how the
 * contact account came to exist:
 *   agent       - provisioned by an agent in the dashboard
 *   portal      - self-registered through the portal
 *   domain-auto - auto-created from an approved+verified email domain
 *   import       - bulk import
 *   email        - reserved for future channel-specific creation
 *
 * All columns nullable or defaulted so existing rows migrate cleanly.
 */
component {

    function up( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.addColumn( table.string( "phone", 50 ).nullable() );
            table.addColumn( table.string( "mobile_phone", 50 ).nullable() );
            table.addColumn( table.string( "job_title", 150 ).nullable() );
            table.addColumn( table.string( "timezone", 64 ).nullable() );
            table.addColumn( table.string( "locale", 20 ).nullable() );
            table.addColumn( table.boolean( "is_vip" ).default( false ) );
            table.addColumn( table.string( "source", 30 ).default( "agent" ) );
            table.addColumn( table.text( "notes" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.dropColumn( "phone" );
            table.dropColumn( "mobile_phone" );
            table.dropColumn( "job_title" );
            table.dropColumn( "timezone" );
            table.dropColumn( "locale" );
            table.dropColumn( "is_vip" );
            table.dropColumn( "source" );
            table.dropColumn( "notes" );
        } );
    }

}
