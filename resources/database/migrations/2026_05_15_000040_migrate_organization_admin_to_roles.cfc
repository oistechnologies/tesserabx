/**
 * Backfill the contact_roles table from the now-deprecated
 * is_organization_admin boolean, then drop the column.
 *
 * Every Contact with is_organization_admin = true gets a row in
 * contact_roles with role_key = 'organization-admin'. The granted_at
 * timestamp defaults to NOW(); granted_by_agent_id stays NULL for the
 * legacy assignments (we don't know who originally granted them).
 *
 * After this runs the canonical home for client-side roles is the
 * contact_roles table; Contact.hasRole reads it through the roles
 * relationship.
 */
component {

    function up( schema, qb ){
        queryExecute( "
            INSERT INTO contact_roles ( id, contact_id, role_key, granted_at )
            SELECT gen_random_uuid()::text, id, 'organization-admin', NOW()
            FROM contacts
            WHERE is_organization_admin = true
            ON CONFLICT ( contact_id, role_key ) DO NOTHING
        " );

        schema.alter( "contacts", function( table ){
            table.dropColumn( "is_organization_admin" );
        } );
    }

    function down( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.addColumn( table.boolean( "is_organization_admin" ).default( false ) );
        } );

        queryExecute( "
            UPDATE contacts
            SET is_organization_admin = true
            WHERE id IN (
                SELECT contact_id FROM contact_roles WHERE role_key = 'organization-admin'
            )
        " );

        queryExecute( "DELETE FROM contact_roles WHERE role_key = 'organization-admin'" );
    }

}
