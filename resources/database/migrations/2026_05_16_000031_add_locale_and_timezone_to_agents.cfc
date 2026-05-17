/**
 * Add timezone and locale to agents.
 *
 * timezone is the IANA zone identifier (e.g. America/Chicago) the
 * application uses when rendering timestamps for this agent. Default
 * UTC matches the project rule: storage is UTC, display follows the
 * viewing user's zone.
 *
 * locale is a BCP-47 language tag (en-US). cbi18n uses it.
 *
 * Separate from the profile migration so the UP statement carries
 * defaults without NULL-then-backfill ceremony on existing rows.
 */
component {

    function up( schema, qb ){
        schema.alter( "agents", function( table ){
            table.addColumn( table.string( "timezone", 100 ).default( "UTC" ) );
            table.addColumn( table.string( "locale", 20 ).default( "en-US" ) );
        } );
    }

    function down( schema, qb ){
        schema.alter( "agents", function( table ){
            table.dropColumn( "locale" );
            table.dropColumn( "timezone" );
        } );
    }

}
