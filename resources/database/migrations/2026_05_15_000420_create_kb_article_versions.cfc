/**
 * Create kb_article_versions: snapshot rows captured on each publish.
 *
 * Phase 2d ships the minimal "history of published versions" so an
 * agent can see what was live when. The current authoring text lives
 * on kb_articles.body; this table records what the visitor actually
 * saw at each publish point.
 *
 * version_number is monotonic per article (1, 2, 3, ...). The
 * unique constraint on (article_id, version_number) catches any
 * accidental retransmission.
 */
component {

    function up( schema, qb ){
        schema.create( "kb_article_versions", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "article_id", 36 ).references( "id" ).onTable( "kb_articles" ).onDelete( "CASCADE" );
            table.integer( "version_number" );
            table.string( "title_snapshot", 500 );
            table.text( "body_snapshot" );
            table.string( "change_note", 500 ).nullable();
            table.string( "published_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            table.timestamp( "published_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "article_id", "version_number" ] );
            table.index( "article_id" );
            table.index( "published_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "kb_article_versions" );
    }

}
