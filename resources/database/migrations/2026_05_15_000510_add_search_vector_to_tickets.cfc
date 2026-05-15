/**
 * Add a STORED tsvector + GIN index to tickets.
 *
 * Searches across subject + originating_email. Cross-message search
 * (matching against ticket_messages.body) is deferred: it requires
 * either a materialized view joining the conversation back to the
 * ticket or per-message tsvectors with an "any-message" search.
 * Phase 2e ships the ticket-row search; Phase 3+ can extend if the
 * usage data justifies it.
 */
component {

    function up( schema, qb ){
        queryExecute( "
            ALTER TABLE tickets
            ADD COLUMN search_vector tsvector
            GENERATED ALWAYS AS (
                setweight( to_tsvector( 'english', coalesce( subject,           '' ) ), 'A' )
                ||
                setweight( to_tsvector( 'english', coalesce( originating_email, '' ) ), 'B' )
            ) STORED
        " );
        queryExecute( "CREATE INDEX idx_tickets_search_vector ON tickets USING GIN ( search_vector )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_tickets_search_vector" );
        queryExecute( "ALTER TABLE tickets DROP COLUMN IF EXISTS search_vector" );
    }

}
