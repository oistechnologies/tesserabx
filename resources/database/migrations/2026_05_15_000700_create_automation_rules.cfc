/**
 * Create automation_rules.
 *
 * Triggers (string column):
 *   - "ticket.created"         fires for both contact and accountless tickets
 *   - "ticket.status_changed"  fires when changeStatus moves the row
 *
 * Conditions and actions are stored as JSON text:
 *   conditions = [ { "field": "priority", "op": "eq", "value": "urgent" }, ... ]   (AND)
 *   actions    = [ { "type": "setPriority", "value": "high" }, ... ]               (sequence)
 *
 * Higher precedence runs first; ties run by name. Provider-side
 * configuration, not tenant-scoped.
 */
component {

    function up( schema, qb ){
        schema.create( "automation_rules", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.text(   "description" ).nullable();
            table.string( "trigger", 40 );
            table.text(   "conditions" );
            table.text(   "actions" );
            table.integer( "precedence" ).default( 0 );
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "trigger" );
            table.index( "is_active" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "automation_rules" );
    }

}
