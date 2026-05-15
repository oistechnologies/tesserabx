/**
 * Create kb_article_feedback: one row per visitor reaction.
 *
 * rating is -1 (not helpful) or +1 (helpful); 0 reserved for a
 * future "neutral" state. contact_id is nullable so an anonymous
 * visitor can leave feedback. ip_hash lets the service de-duplicate
 * repeat votes from the same address without persisting raw IPs.
 */
component {

    function up( schema, qb ){
        schema.create( "kb_article_feedback", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "article_id", 36 ).references( "id" ).onTable( "kb_articles" ).onDelete( "CASCADE" );
            table.string( "contact_id", 36 ).nullable().references( "id" ).onTable( "contacts" ).onDelete( "SET NULL" );
            table.string( "ip_hash", 64 ).nullable();
            table.smallInteger( "rating" );
            table.text( "comment" ).nullable();
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "article_id" );
            table.index( [ "article_id", "ip_hash" ], "idx_kb_feedback_article_ip" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "kb_article_feedback" );
    }

}
