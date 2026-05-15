/**
 * Track which (rule, ticket) pairs an escalation-style rule has
 * already fired against, so the periodic scheduler scan does not
 * re-trigger the same action every 5 minutes for the lifetime of
 * the ticket.
 *
 * Phase 3e dedup only applies to recurring triggers
 * (currently `ticket.escalation`). One-shot event triggers
 * (`ticket.created`, `ticket.status_changed`) bypass this table.
 *
 * Composite primary key on (rule_id, ticket_id) makes "already fired"
 * a simple constraint-violation check on insert.
 */
component {

    function up( schema, qb ){
        queryExecute( "
            CREATE TABLE automation_rule_fires (
                rule_id   VARCHAR(36) NOT NULL,
                ticket_id VARCHAR(36) NOT NULL,
                fired_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY ( rule_id, ticket_id )
            )
        " );
        queryExecute( "CREATE INDEX idx_automation_rule_fires_ticket_id ON automation_rule_fires ( ticket_id )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP TABLE IF EXISTS automation_rule_fires" );
    }

}
