/**
 * Create business_hours_calendars.
 *
 * Provider-side configuration, not tenant-scoped. The SLA service
 * picks a calendar by policy, not by the requesting organization, so
 * calendars sit outside the contacts global scope.
 *
 * weekly_hours and holidays are stored as JSONB:
 *   weekly_hours = {
 *       "mon": [ { "start": "09:00", "end": "17:00" } ],
 *       "tue": [ ... ],
 *       ...
 *       "sun": []
 *   }
 *   holidays = [ "2026-01-01", "2026-12-25", ... ]
 *
 * is_default flags the calendar the SLA service uses when a policy
 * does not name one. A partial unique index guarantees only one row
 * can hold is_default = true.
 */
component {

    function up( schema, qb ){
        schema.create( "business_hours_calendars", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.string( "timezone", 64 ).default( "UTC" );
            // Stored as JSON text. Kept as text rather than json/jsonb so
            // the JDBC driver does not require a typed binding; the
            // SlaService deserializes on read.
            table.text( "weekly_hours" );
            table.text( "holidays" );
            table.boolean( "is_default" ).default( false );
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "is_active" );
        } );

        queryExecute( "
            CREATE UNIQUE INDEX uq_business_hours_calendars_one_default
            ON business_hours_calendars ( is_default )
            WHERE is_default = TRUE
        " );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS uq_business_hours_calendars_one_default" );
        schema.drop( "business_hours_calendars" );
    }

}
