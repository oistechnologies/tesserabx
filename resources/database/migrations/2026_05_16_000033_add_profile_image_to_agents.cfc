/**
 * Add profile image metadata columns to agents.
 *
 * profile_image_original_path is the CBFS-relative path to the
 * original upload. Thumbnails live at deterministic sibling paths
 * derived from this base; only the original path is persisted here.
 *
 * profile_image_content_type holds the original file's MIME so the
 * serving handler can set the correct Content-Type on responses.
 *
 * profile_image_uploaded_at participates in the avatar URL as a
 * cache-busting query string so browsers refetch after a re-upload
 * even though the URL path is otherwise stable.
 *
 * No FK on the path column: CBFS paths are opaque to the database.
 */
component {

    function up( schema, qb ){
        schema.alter( "agents", function( table ){
            table.addColumn( table.string( "profile_image_original_path", 500 ).nullable() );
            table.addColumn( table.string( "profile_image_content_type", 100 ).nullable() );
            table.addColumn( table.timestamp( "profile_image_uploaded_at" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "agents", function( table ){
            table.dropColumn( "profile_image_uploaded_at" );
            table.dropColumn( "profile_image_content_type" );
            table.dropColumn( "profile_image_original_path" );
        } );
    }

}
