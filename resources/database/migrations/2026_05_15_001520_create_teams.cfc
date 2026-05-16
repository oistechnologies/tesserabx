/**
 * Create teams + team_members.
 *
 * A Team groups agents for routing, reporting, and notification
 * fan-out. The membership is many-to-many: an agent can sit on
 * multiple teams (e.g. "Tier 1" and "On-call").
 *
 * role_in_team is a free text slot (default "member", common values
 * "lead") that lets a team designate a primary contact without a
 * second table. The team-level admin permission still flows through
 * the agent_roles RBAC; this column is a hint for routing.
 */
component {

    function up( schema, qb ){
        schema.create( "teams", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.string( "description", 500 ).nullable();
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( "name" );
            table.index( "is_active" );
        } );

        schema.create( "team_members", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "team_id", 36 ).references( "id" ).onTable( "teams" ).onDelete( "CASCADE" );
            table.string( "agent_id", 36 ).references( "id" ).onTable( "agents" ).onDelete( "CASCADE" );
            table.string( "role_in_team", 50 ).default( "member" );
            table.timestamp( "joined_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "team_id", "agent_id" ] );
            table.index( "team_id" );
            table.index( "agent_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "team_members" );
        schema.drop( "teams" );
    }

}
