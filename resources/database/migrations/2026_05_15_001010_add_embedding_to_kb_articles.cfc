/**
 * Add a pgvector embedding column to kb_articles for semantic
 * search (Phase 4e).
 *
 * Dimension is fixed at 1536 to match OpenAI text-embedding-3-small,
 * which is the configured default. Changing AI_EMBEDDING_MODEL to a
 * model with a different dimension requires altering this column.
 *
 * The index uses HNSW with vector_cosine_ops because cosine
 * similarity is the standard distance metric for embedding-based
 * semantic search. ANALYZE after backfilling embeddings to refresh
 * planner stats.
 *
 * pgvector was enabled by Phase 0's baseline_extensions migration.
 */
component {

    function up( schema, qb ){
        queryExecute( "ALTER TABLE kb_articles ADD COLUMN embedding vector(1536)" );
        queryExecute( "CREATE INDEX idx_kb_articles_embedding_hnsw ON kb_articles USING hnsw ( embedding vector_cosine_ops )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_kb_articles_embedding_hnsw" );
        queryExecute( "ALTER TABLE kb_articles DROP COLUMN IF EXISTS embedding" );
    }

}
