/**
 * Create ticket_approvals.
 *
 * B8: per-ticket approval requests. A row is created by the
 * `requestApproval` automation action (or any caller of
 * ApprovalService.requestApproval) and decided by the named approver
 * via the ticket-detail panel.
 *
 * v1 is a single-approver model: one ticket can have one open
 * approval row; deciding it locks it (status moves off "pending"
 * and decided_at stamps). Future versions will model chains via a
 * separate ticket_approval_steps table; for v1 the simpler shape
 * lets the UX land first.
 *
 * organization_id mirrors the parent ticket's value (nullable for
 * accountless tickets). Tenant scope follows the parent ticket FK;
 * this column exists for direct queries that filter approvals by
 * tenant without joining tickets.
 */
component {

    function up( schema, qb ){
        schema.create( "ticket_approvals", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "ticket_id", 36 )
                 .references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );
            table.string( "requested_by_agent_id", 36 ).nullable();
            table.string( "approver_agent_id", 36 ).nullable()
                 .references( "id" ).onTable( "agents" );
            table.string( "organization_id", 36 ).nullable()
                 .references( "id" ).onTable( "organizations" );
            // pending | approved | rejected
            table.string( "status", 20 ).default( "pending" );
            table.timestamp( "decided_at" ).nullable();
            table.text( "comment" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "ticket_id" );
            table.index( "approver_agent_id" );
            table.index( "status" );
            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "ticket_approvals" );
    }

}
