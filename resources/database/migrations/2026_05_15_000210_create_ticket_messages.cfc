/**
 * Create ticket_messages: the threaded conversation log per ticket.
 *
 * A message has either an author_contact_id (client reply), an
 * author_agent_id (provider reply), or neither (inbound email from
 * an unrecognized sender; the raw author_email is captured instead).
 *
 * is_internal flags an agent-only note that NEVER reaches any
 * client-side role, per CLAUDE.md's hard constraint. The /portal and
 * /widget surfaces filter on this flag; tests verify that filtering.
 */
component {

    function up( schema, qb ){
        schema.create( "ticket_messages", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "ticket_id", 36 ).references( "id" ).onTable( "tickets" ).onDelete( "CASCADE" );

            table.string( "author_contact_id", 36 ).nullable().references( "id" ).onTable( "contacts" ).onDelete( "SET NULL" );
            table.string( "author_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            // Raw sender address for inbound emails before a contact
            // is resolved or created. Stays populated alongside the
            // FK once a contact is provisioned, for traceability.
            table.string( "author_email", 320 ).nullable();

            table.text( "body" );
            table.boolean( "is_internal" ).default( false );

            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "ticket_id" );
            table.index( "created_at" );
            table.index( "is_internal" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "ticket_messages" );
    }

}
