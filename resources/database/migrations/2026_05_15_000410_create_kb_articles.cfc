/**
 * Create kb_articles: knowledge-base article rows.
 *
 * visibility is one of "public", "organization", "internal":
 *   - public:       anyone, including unauthenticated visitors
 *   - organization: scoped to one or more orgs via the
 *                   kb_article_organizations join (many-to-many)
 *   - internal:     provider agents only
 *
 * status is "draft" or "published". A draft is editable from the
 * admin UI but never visible on the portal read surfaces.
 *
 * body holds the current authoring text. kb_article_versions
 * snapshots a copy on each publish so historical reads are still
 * possible without a full ORM-versioned-entity setup.
 */
component {

    function up( schema, qb ){
        schema.create( "kb_articles", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "title", 500 );
            table.string( "slug", 250 ).unique();
            table.text( "body" );
            table.string( "category_id", 36 ).nullable().references( "id" ).onTable( "kb_categories" ).onDelete( "SET NULL" );

            table.string( "visibility", 20 ).default( "internal" );
            table.string( "status", 20 ).default( "draft" );

            table.string( "author_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            table.bigInteger( "view_count" ).default( 0 );

            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "published_at" ).nullable();

            table.index( "category_id" );
            table.index( "visibility" );
            table.index( "status" );
            table.index( "published_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "kb_articles" );
    }

}
