/**
 * Backfill SLA on tickets that pre-date Phase 3b.
 *
 * Existing rows have no sla_policy_id and therefore render as "No SLA"
 * in the agent UI. This migration retroactively stamps the default
 * policy on every still-active ticket (status NOT IN resolved/closed)
 * and seeds first_response_due_at + resolution_due_at by adding the
 * policy's target minutes to each ticket's created_at, treated as a
 * literal wall-clock offset rather than business-hours-aware. The
 * Phase 3e scheduler will recompute properly the next time it runs;
 * this just lights up the UI today.
 *
 * Idempotent: only touches rows where sla_policy_id IS NULL.
 *
 * If no default policy exists yet (e.g., the seeder has not been run),
 * the migration is a no-op.
 */
component {

    function up( schema, qb ){
        var policyRow = queryExecute(
            "SELECT id, first_response_minutes, resolution_minutes
             FROM   sla_policies
             WHERE  is_default = TRUE
             AND    is_active  = TRUE
             LIMIT  1"
        );
        if ( !policyRow.recordCount ) return;
        var policyId = policyRow.id[ 1 ];
        var frMin    = policyRow.first_response_minutes[ 1 ];
        var resMin   = policyRow.resolution_minutes[ 1 ];

        // The minute values come from a trusted query against the same
        // database; we int() them and inline so the JDBC binder does not
        // send them as varchar (which breaks make_interval's signature)
        // and so '::INTERVAL' casts do not collide with ':name'
        // parameter substitution. The only bound parameter is the
        // policy id.
        var frInt  = int( frMin );
        var resInt = int( resMin );
        queryExecute(
            "UPDATE tickets
             SET    sla_policy_id         = :pid,
                    first_response_due_at = created_at + make_interval( mins => #frInt# ),
                    resolution_due_at     = created_at + make_interval( mins => #resInt# )
             WHERE  sla_policy_id IS NULL
             AND    status NOT IN ( 'resolved', 'closed' )",
            { pid : policyId }
        );
    }

    function down( schema, qb ){
        // No-op. Reverting Phase 3b drops the columns wholesale via
        // 2026_05_15_000620; we do not try to selectively un-backfill.
    }

}
