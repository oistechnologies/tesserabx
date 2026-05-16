/**
 * Create ticket_statuses + ticket_status_transitions.
 *
 * Replaces the hardcoded STATUSES / TRANSITIONS / PAUSED_STATUSES
 * arrays in TicketsService with an admin-editable catalog. Each
 * status carries a `category` enum (open | paused | resolved |
 * closed) that the rest of the platform reads to decide SLA
 * pause semantics, terminal exclusion in breach queries, and the
 * resolved_at / closed_at stamping in changeStatus.
 *
 * Tickets.status stays as a varchar string keyed against
 * ticket_statuses.key — no FK so an admin can deactivate a status
 * without breaking historical tickets that already used it.
 *
 * Seeds the six statuses that TicketsService shipped with so an
 * upgrading deployment keeps its existing transitions.
 */
component {

    function up( schema, qb ){
        schema.create( "ticket_statuses", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "key", 50 ).unique();
            table.string( "label", 100 );
            table.string( "category", 20 );
            table.string( "badge_class", 50 ).default( "secondary" );
            table.integer( "sort_order" ).default( 0 );
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "category" );
            table.index( "is_active" );
        } );

        schema.create( "ticket_status_transitions", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "from_key", 50 );
            table.string( "to_key", 50 );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "from_key", "to_key" ] );
            table.index( "from_key" );
        } );

        // Seed the documented status set.
        var seed = [
            { key : "new",      label : "New",      category : "open",     badge_class : "primary",   sort_order : 10 },
            { key : "open",     label : "Open",     category : "open",     badge_class : "info",      sort_order : 20 },
            { key : "pending",  label : "Pending",  category : "paused",   badge_class : "warning",   sort_order : 30 },
            { key : "on-hold",  label : "On hold",  category : "paused",   badge_class : "secondary", sort_order : 40 },
            { key : "resolved", label : "Resolved", category : "resolved", badge_class : "success",   sort_order : 50 },
            { key : "closed",   label : "Closed",   category : "closed",   badge_class : "dark",      sort_order : 60 }
        ];
        for ( var row in seed ) {
            queryExecute(
                "INSERT INTO ticket_statuses
                    ( id, key, label, category, badge_class, sort_order, is_active )
                 VALUES
                    ( :id, :k, :l, :c, :bc, cast( :so as integer ), TRUE )",
                {
                    id : createUUID(),
                    k  : row.key,
                    l  : row.label,
                    c  : row.category,
                    bc : row.badge_class,
                    so : toString( row.sort_order )
                }
            );
        }

        // Seed transitions to match what TicketsService.TRANSITIONS
        // shipped with. New deployments inherit the same workflow;
        // an admin can add or remove rows from here freely.
        var transitions = {
            "new"      : [ "open", "on-hold", "resolved", "closed" ],
            "open"     : [ "pending", "on-hold", "resolved", "closed" ],
            "pending"  : [ "open", "on-hold", "resolved", "closed" ],
            "on-hold"  : [ "open", "pending", "resolved", "closed" ],
            "resolved" : [ "open", "closed" ],
            "closed"   : [ "open" ]
        };
        for ( var from in transitions ) {
            for ( var to in transitions[ from ] ) {
                queryExecute(
                    "INSERT INTO ticket_status_transitions ( id, from_key, to_key )
                     VALUES ( :id, :f, :t )",
                    { id : createUUID(), f : from, t : to }
                );
            }
        }
    }

    function down( schema, qb ){
        schema.drop( "ticket_status_transitions" );
        schema.drop( "ticket_statuses" );
    }

}
