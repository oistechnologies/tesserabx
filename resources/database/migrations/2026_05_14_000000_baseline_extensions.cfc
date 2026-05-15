/**
 * Baseline migration: enable required PostgreSQL extensions.
 *
 * pgvector handles vector similarity search natively (no separate vector
 * store). pgcrypto provides gen_random_uuid() and digest functions.
 * citext gives case-insensitive text columns (used for email).
 *
 * The migration runner passes a qb instance bound to the active
 * datasource; we use raw statements through it so the datasource name
 * (`cfmigrations` in CLI mode, `tesserabx` in-app) doesn't have to be
 * hardcoded.
 */
component {

    function up( schema, qb ){
        queryExecute( "CREATE EXTENSION IF NOT EXISTS pgcrypto" );
        queryExecute( "CREATE EXTENSION IF NOT EXISTS vector" );
        queryExecute( "CREATE EXTENSION IF NOT EXISTS citext" );
    }

    function down( schema, qb ){
        queryExecute( "DROP EXTENSION IF EXISTS citext" );
        queryExecute( "DROP EXTENSION IF EXISTS vector" );
        queryExecute( "DROP EXTENSION IF EXISTS pgcrypto" );
    }

}
