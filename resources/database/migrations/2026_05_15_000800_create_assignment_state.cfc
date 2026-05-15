/**
 * Tiny key/value table that anchors round-robin pointers across
 * server restarts. One row per strategy key (e.g., "default" for the
 * global pool, or a team id later when teams land). `last_agent_id`
 * is the most-recently picked agent; the next round-robin choice
 * starts after that agent in the sorted-id order.
 *
 * No FK to agents because that agent may be deleted; the pointer
 * still works (we just skip past the dead id).
 */
component {

    function up( schema, qb ){
        schema.create( "assignment_state", function( table ){
            table.string( "strategy_key", 64 ).primaryKey();
            table.string( "last_agent_id", 36 ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "assignment_state" );
    }

}
