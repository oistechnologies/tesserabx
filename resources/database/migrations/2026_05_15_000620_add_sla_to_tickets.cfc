/**
 * Add SLA columns to tickets.
 *
 * sla_policy_id        — the policy the ticket was opened under. Stamped
 *                        at create time, not mutated by status changes.
 *                        FK uses SET NULL on delete so an admin can drop
 *                        a stale policy without orphaning history.
 * first_response_due_at — UTC instant by which an agent must reply.
 * resolution_due_at     — UTC instant by which the ticket must reach
 *                        resolved or closed.
 * first_response_at     — UTC instant of the actual first agent reply,
 *                        for FR-met tracking. NULL until an agent posts
 *                        a non-internal message.
 * sla_paused_at         — UTC instant the ticket entered a paused
 *                        status (pending / on-hold). NULL when active.
 *                        On unpause the service shifts both due_at
 *                        columns forward by the business-minutes that
 *                        elapsed during the pause, then clears this.
 *
 * Indexes on the two due_at columns support the breach-scan query in
 * the scheduler (Phase 3e).
 */
component {

    function up( schema, qb ){
        queryExecute( "
            ALTER TABLE tickets
                ADD COLUMN sla_policy_id          VARCHAR(36),
                ADD COLUMN first_response_due_at  TIMESTAMP,
                ADD COLUMN resolution_due_at      TIMESTAMP,
                ADD COLUMN first_response_at      TIMESTAMP,
                ADD COLUMN sla_paused_at          TIMESTAMP
        " );
        queryExecute( "
            ALTER TABLE tickets
                ADD CONSTRAINT fk_tickets_sla_policy
                FOREIGN KEY ( sla_policy_id )
                REFERENCES sla_policies ( id )
                ON DELETE SET NULL
        " );
        queryExecute( "CREATE INDEX idx_tickets_first_response_due_at ON tickets ( first_response_due_at )" );
        queryExecute( "CREATE INDEX idx_tickets_resolution_due_at     ON tickets ( resolution_due_at )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_tickets_resolution_due_at" );
        queryExecute( "DROP INDEX IF EXISTS idx_tickets_first_response_due_at" );
        queryExecute( "ALTER TABLE tickets DROP CONSTRAINT IF EXISTS fk_tickets_sla_policy" );
        queryExecute( "
            ALTER TABLE tickets
                DROP COLUMN IF EXISTS sla_paused_at,
                DROP COLUMN IF EXISTS first_response_at,
                DROP COLUMN IF EXISTS resolution_due_at,
                DROP COLUMN IF EXISTS first_response_due_at,
                DROP COLUMN IF EXISTS sla_policy_id
        " );
    }

}
