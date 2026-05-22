/**
 * Create kb_article_custom_field_values.
 *
 * Phase 9 of the extensibility plan generalizes custom fields beyond
 * tickets. Same typed-column layout as ticket_custom_field_values;
 * the entity column is article_id, foreign-keyed to kb_articles.
 *
 * KB articles carry a three-tier visibility (public, organization-
 * scoped, internal); the value rows inherit that visibility from the
 * parent article and have no tenancy column of their own.
 */
component {

    function up( schema, qb ){
        schema.create( "kb_article_custom_field_values", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "article_id", 36 ).references( "id" ).onTable( "kb_articles" ).onDelete( "CASCADE" );
            table.string( "definition_id", 36 ).references( "id" ).onTable( "custom_field_definitions" ).onDelete( "CASCADE" );
            table.text( "value_text" ).nullable();
            table.decimal( "value_number", 20, 6 ).nullable();
            table.timestamp( "value_date" ).nullable();
            table.boolean( "value_boolean" ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );

            table.unique( [ "article_id", "definition_id" ] );
            table.index( "article_id" );
            table.index( "definition_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "kb_article_custom_field_values" );
    }

}
