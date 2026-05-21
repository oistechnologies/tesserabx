/**
 * Add the `source` column to audit_events for add-on origin tracking.
 *
 * Core events (everything announced from modules_app/) land with
 * source = NULL (or 'core' if a future migration backfills). Add-on
 * events declared via settings.tesserabx.auditEvents = [...] in an
 * add-on's ModuleConfig.bx are recorded by AuditService.record() with
 * source = the addon_id. The admin audit search UI exposes a source
 * filter dropdown so an operator can inspect everything an add-on
 * has done independently of core noise.
 */
component {

    function up( schema, qb ){
        schema.alter( "audit_events", function( table ){
            table.addColumn( table.string( "source", 100 ).nullable() );
        } );
        queryExecute( "CREATE INDEX idx_audit_source ON audit_events ( source )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_audit_source" );
        schema.alter( "audit_events", function( table ){
            table.dropColumn( "source" );
        } );
    }

}
