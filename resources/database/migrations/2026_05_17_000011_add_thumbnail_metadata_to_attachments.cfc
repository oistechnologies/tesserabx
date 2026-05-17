/**
 * Image thumbnail metadata on attachments.
 *
 * thumbnail_status tracks the per-attachment lifecycle:
 *   - pending     : image upload accepted; thumbnail not yet built
 *   - ready       : thumbnail exists at <cbfs_path>.thumb.jpg
 *   - unsupported : non-image attachment; no thumbnail will be built
 *   - failed      : thumbnail generation attempted and errored;
 *                   the original file is still served correctly
 *
 * thumbnail_generated_at captures when "ready" was reached so the
 * <img src> cache-buster can stay stable across re-renders.
 */
component {

    function up( schema, qb ){
        schema.alter( "attachments", function( table ){
            table.addColumn( table.string( "thumbnail_status", 20 ).default( "pending" ) );
            table.addColumn( table.timestamp( "thumbnail_generated_at" ).nullable() );
        } );
        queryExecute( "CREATE INDEX idx_attachments_thumbnail_status ON attachments ( thumbnail_status )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_attachments_thumbnail_status" );
        schema.alter( "attachments", function( table ){
            table.dropColumn( "thumbnail_generated_at" );
            table.dropColumn( "thumbnail_status" );
        } );
    }

}
