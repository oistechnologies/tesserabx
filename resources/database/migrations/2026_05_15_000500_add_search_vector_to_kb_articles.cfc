/**
 * Add a STORED tsvector + GIN index to kb_articles.
 *
 * Postgres generated columns (12+) keep search_vector in sync with
 * title + body on every write, so no triggers or application-side
 * updates are needed. setweight tags title higher than body so a
 * match in the title outranks a match in the body on
 * ts_rank_cd ordering.
 */
component {

    function up( schema, qb ){
        queryExecute( "
            ALTER TABLE kb_articles
            ADD COLUMN search_vector tsvector
            GENERATED ALWAYS AS (
                setweight( to_tsvector( 'english', coalesce( title, '' ) ), 'A' )
                ||
                setweight( to_tsvector( 'english', coalesce( body,  '' ) ), 'B' )
            ) STORED
        " );
        queryExecute( "CREATE INDEX idx_kb_articles_search_vector ON kb_articles USING GIN ( search_vector )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_kb_articles_search_vector" );
        queryExecute( "ALTER TABLE kb_articles DROP COLUMN IF EXISTS search_vector" );
    }

}
