/**
 * Create scheduled_exports: admin-configured recurring data exports.
 *
 * Each row drives one recurring CSV export of tickets matching the
 * filters JSON. The scheduler task in config/Scheduler.bx picks rows
 * whose next_run_at is in the past, materializes the CSV, drops it
 * onto the default CBFS provider under exports/, stamps last_run_at
 * + last_file_path, advances next_run_at by interval_minutes, and
 * mails the recipients an "export ready" notification.
 *
 * Format is fixed at CSV today; the column is here so a JSON or
 * Parquet variant in the future does not require a migration.
 *
 * filters_json and recipients_json are TEXT (not jsonb) because the
 * JDBC binder cannot send a typed jsonb value through the named
 * parameter pipeline; ScheduledExportService deserializes on read.
 */
component {

    function up( schema, qb ){
        schema.create( "scheduled_exports", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.string( "format", 16 ).default( "csv" );
            table.text(   "filters_json" );
            table.text(   "recipients_json" );
            table.integer( "interval_minutes" ).default( 1440 );
            table.timestamp( "next_run_at" ).nullable();
            table.timestamp( "last_run_at" ).nullable();
            table.string( "last_file_path", 500 ).nullable();
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "next_run_at" );
            table.index( "is_active" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "scheduled_exports" );
    }

}
