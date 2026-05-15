/**
 * Create ai_interactions: the audit log for every AI call.
 *
 * The AI middleware facade writes one row per provider call,
 * regardless of outcome. Every row carries the feature key the
 * caller named so we can slice usage and cost by feature
 * (suggested-reply vs. triage vs. summarize, etc.).
 *
 * Identifying columns (organization_id / ticket_id / contact_id /
 * agent_id) are all nullable so AI features that do not have a
 * subject (e.g., dev smoke tests, broad searches) still log without
 * forcing a phony id.
 *
 * `prompt_hash` is a SHA-256 of the prompt after PII redaction; the
 * raw prompt is not persisted. Token counts and latency are recorded
 * for cost and performance dashboards. `outcome` is one of:
 *   ok | timeout | error | disabled | redacted_only
 * (disabled = the capability flag was off when the caller asked;
 * redacted_only = the redactor stripped everything and we refused
 * to send.)
 *
 * Not tenant-scoped at the row level: provider-side observability
 * log. Filtering by organization in reports is via the column, not
 * a global scope.
 */
component {

    function up( schema, qb ){
        schema.create( "ai_interactions", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "feature", 64 );
            // provider + model are nullable so a "disabled" or
            // "redacted_only" row that fires before any provider is
            // configured still logs without a phony placeholder.
            table.string( "provider", 64 ).nullable();
            table.string( "model", 128 ).nullable();
            table.string( "prompt_hash", 64 ).nullable();
            table.integer( "tokens_in" ).default( 0 );
            table.integer( "tokens_out" ).default( 0 );
            table.integer( "latency_ms" ).default( 0 );
            table.string( "outcome", 32 );
            table.text(   "error_message" ).nullable();

            table.string( "organization_id", 36 ).nullable();
            table.string( "ticket_id", 36 ).nullable();
            table.string( "contact_id", 36 ).nullable();
            table.string( "agent_id", 36 ).nullable();

            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "feature" );
            table.index( "outcome" );
            table.index( "created_at" );
            table.index( "organization_id" );
            table.index( "ticket_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "ai_interactions" );
    }

}
