/**
 * Persist the AI thread summary on each ticket.
 *
 * ai_summary is the JSON struct produced by SummarizationService
 * ({summary, keyPoints, nextStep}); ai_summary_at stamps when it was
 * generated so the agent UI can show "as of YYYY-MM-DD HH:MM". A
 * fresh "Refresh" overwrites both columns; null means "never run".
 */
component {

    function up( schema, qb ){
        queryExecute( "
            ALTER TABLE tickets
                ADD COLUMN ai_summary    TEXT,
                ADD COLUMN ai_summary_at TIMESTAMP
        " );
    }

    function down( schema, qb ){
        queryExecute( "ALTER TABLE tickets DROP COLUMN IF EXISTS ai_summary_at, DROP COLUMN IF EXISTS ai_summary" );
    }

}
