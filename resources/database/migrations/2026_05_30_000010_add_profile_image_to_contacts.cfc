/**
 * Add profile image metadata columns to contacts.
 *
 * Mirrors the agent profile-image columns (see
 * 2026_05_16_000033_add_profile_image_to_agents.cfc). Contact avatars
 * follow the same pipeline (ImageProcessingService + AvatarHelper) but
 * under the "contacts" prefix on the public CBFS disk:
 *   public-files/contacts/<id>/profile/<size>.jpg
 *
 * profile_image_original_path is the CBFS-relative path to the
 * original upload; thumbnails live at deterministic sibling paths.
 * profile_image_content_type holds the original MIME. The
 * profile_image_uploaded_at timestamp is the avatar URL cache-buster.
 */
component {

    function up( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.addColumn( table.string( "profile_image_original_path", 500 ).nullable() );
            table.addColumn( table.string( "profile_image_content_type", 100 ).nullable() );
            table.addColumn( table.timestamp( "profile_image_uploaded_at" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.dropColumn( "profile_image_uploaded_at" );
            table.dropColumn( "profile_image_content_type" );
            table.dropColumn( "profile_image_original_path" );
        } );
    }

}
