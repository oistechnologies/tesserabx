/**
 * Create kb_article_organizations: many-to-many join between
 * articles and the organizations that can see them.
 *
 * Only relevant for articles with visibility = "organization". A
 * row here grants one organization access; multiple rows fan-out
 * the same article to several orgs. visibility = "public" or
 * "internal" articles ignore this table entirely.
 */
component {

    function up( schema, qb ){
        schema.create( "kb_article_organizations", function( table ){
            table.string( "article_id", 36 ).references( "id" ).onTable( "kb_articles" ).onDelete( "CASCADE" );
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.primaryKey( [ "article_id", "organization_id" ] );
            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "kb_article_organizations" );
    }

}
