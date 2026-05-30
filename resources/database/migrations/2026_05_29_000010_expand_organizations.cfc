/**
 * Expand organizations with support-CRM attributes.
 *
 * The tenant boundary started life with just name, slug, tier, and an
 * active flag. Real support work needs an account reference, a contact
 * point, a mailing address, a lifecycle status, and a default display
 * time zone. All columns are nullable or defaulted so the migration
 * applies cleanly to existing rows.
 *
 * Two columns drive behavior beyond display:
 *   - auto_provision_contacts: when true, an inbound email from one of
 *     this org's verified approved domains auto-creates a Contact (see
 *     ContactsService.resolveOrAutoProvisionContact and the channels
 *     inbound flow).
 *   - primary_contact_id: the org's main point of contact. FK to
 *     contacts with ON DELETE SET NULL so deleting that contact does
 *     not orphan the org. Declared via raw SQL (qb's alter path does
 *     not chain a foreign key onto addColumn); mirrors
 *     2026_05_16_000032_add_manager_to_agents.
 */
component {

    function up( schema, qb ){
        schema.alter( "organizations", function( table ){
            table.addColumn( table.string( "account_number", 100 ).nullable() );
            table.addColumn( table.string( "status", 30 ).default( "active" ) );
            table.addColumn( table.string( "phone", 50 ).nullable() );
            table.addColumn( table.string( "website", 255 ).nullable() );
            table.addColumn( table.string( "industry", 100 ).nullable() );
            table.addColumn( table.string( "address_line1", 255 ).nullable() );
            table.addColumn( table.string( "address_line2", 255 ).nullable() );
            table.addColumn( table.string( "city", 120 ).nullable() );
            table.addColumn( table.string( "region", 120 ).nullable() );
            table.addColumn( table.string( "postal_code", 20 ).nullable() );
            table.addColumn( table.string( "country", 2 ).nullable() );
            table.addColumn( table.string( "timezone", 64 ).nullable() );
            table.addColumn( table.text( "notes" ).nullable() );
            table.addColumn( table.boolean( "auto_provision_contacts" ).default( false ) );
            table.addColumn( table.string( "primary_contact_id", 36 ).nullable() );
        } );
        queryExecute(
            "ALTER TABLE organizations
             ADD CONSTRAINT fk_organizations_primary_contact_id
             FOREIGN KEY ( primary_contact_id ) REFERENCES contacts ( id )
             ON DELETE SET NULL"
        );
        queryExecute( "CREATE INDEX idx_organizations_primary_contact_id ON organizations ( primary_contact_id )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_organizations_primary_contact_id" );
        queryExecute( "ALTER TABLE organizations DROP CONSTRAINT IF EXISTS fk_organizations_primary_contact_id" );
        schema.alter( "organizations", function( table ){
            table.dropColumn( "account_number" );
            table.dropColumn( "status" );
            table.dropColumn( "phone" );
            table.dropColumn( "website" );
            table.dropColumn( "industry" );
            table.dropColumn( "address_line1" );
            table.dropColumn( "address_line2" );
            table.dropColumn( "city" );
            table.dropColumn( "region" );
            table.dropColumn( "postal_code" );
            table.dropColumn( "country" );
            table.dropColumn( "timezone" );
            table.dropColumn( "notes" );
            table.dropColumn( "auto_provision_contacts" );
            table.dropColumn( "primary_contact_id" );
        } );
    }

}
