/**
 * Create attachments: file uploads bound to a ticket or message.
 *
 * cbfs_path is the relative path on the configured CBFS disk
 * (local for dev, S3-compatible for shared/staging/prod). The
 * application streams via signed URL or behind cbSecurity per the
 * deployment's CBFS provider; the path itself never goes raw to a
 * client. Upload size and content type validation happen in the
 * tickets service; this table just records what landed.
 */
component {

    function up( schema, qb ){
        schema.create( "attachments", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "ticket_id", 36 ).nullable().references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );
            table.string( "message_id", 36 ).nullable().references( "id" ).onTable( "ticket_messages" ).onDelete( "CASCADE" );

            table.string( "uploader_contact_id", 36 ).nullable().references( "id" ).onTable( "contacts" ).onDelete( "SET NULL" );
            table.string( "uploader_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );

            table.string( "original_filename", 500 );
            table.string( "content_type", 200 );
            table.bigInteger( "size_bytes" );
            table.text( "cbfs_path" );

            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "ticket_id" );
            table.index( "message_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "attachments" );
    }

}
