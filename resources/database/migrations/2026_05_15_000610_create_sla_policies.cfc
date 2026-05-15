/**
 * Create sla_policies.
 *
 * A policy declares first-response and resolution targets in minutes
 * of business time, evaluated against a BusinessHoursCalendar. Each
 * policy may scope itself by ticket priority and / or by the
 * requesting organization's tier; NULL on either column means "any".
 *
 * Provider-side configuration: not tenant-scoped. Matching favors
 * specificity: priority + tier beats priority-only beats tier-only
 * beats default. Ties break on `precedence` descending.
 *
 * is_default flags the fallback policy when nothing else matches. A
 * partial unique index guarantees only one row holds is_default.
 */
component {

    function up( schema, qb ){
        schema.create( "sla_policies", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.text( "description" ).nullable();
            table.string( "priority", 20 ).nullable();
            table.string( "tier", 64 ).nullable();
            table.integer( "first_response_minutes" );
            table.integer( "resolution_minutes" );
            table.string( "business_hours_calendar_id", 36 )
                 .nullable()
                 .references( "id" ).onTable( "business_hours_calendars" ).onDelete( "SET NULL" );
            table.integer( "precedence" ).default( 0 );
            table.boolean( "is_default" ).default( false );
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "priority" );
            table.index( "tier" );
            table.index( "is_active" );
        } );

        queryExecute( "
            CREATE UNIQUE INDEX uq_sla_policies_one_default
            ON sla_policies ( is_default )
            WHERE is_default = TRUE
        " );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS uq_sla_policies_one_default" );
        schema.drop( "sla_policies" );
    }

}
