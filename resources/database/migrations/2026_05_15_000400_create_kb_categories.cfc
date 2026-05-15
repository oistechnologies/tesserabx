/**
 * Create kb_categories: knowledge-base category / folder hierarchy.
 *
 * parent_id is a self-reference (NULLABLE) so a category can either
 * sit at the root or under a parent. The slug is unique within the
 * application (not per parent) so URLs at /kb/<slug> stay
 * unambiguous; nested URLs come from the article slug, not the
 * category tree.
 */
component {

    function up( schema, qb ){
        schema.create( "kb_categories", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "name", 200 );
            table.string( "slug", 200 ).unique();
            table.string( "parent_id", 36 ).nullable().references( "id" ).onTable( "kb_categories" ).onDelete( "SET NULL" );
            table.integer( "sort_order" ).default( 0 );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "parent_id" );
            table.index( "sort_order" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "kb_categories" );
    }

}
