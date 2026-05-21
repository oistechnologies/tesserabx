/**
 * Create addon registry tables: global addon record and per-organization
 * enablement overrides.
 *
 * Foundation of the TesseraBX extensibility surface. An add-on is a
 * standard ColdBox module (in modules/ or modules_app/) that ships a
 * settings.tesserabx manifest block in its ModuleConfig.bx. At app
 * boot the AddonRegistryService reads each manifest and upserts a row
 * into addons. Per-organization overrides land in
 * addon_organization_enablement.
 *
 * Resolution rule (implemented in AddonRegistryService.isEnabled):
 *   - addons.enabled = false                  ⇒ off everywhere
 *   - enablement_mode = 'all'                 ⇒ on for every organization
 *   - enablement_mode = 'specific'            ⇒ on only when an
 *                                               addon_organization_enablement
 *                                               row exists with enabled = true
 */
component {

    function up( schema, qb ){
        schema.create( "addons", function( table ){
            table.string( "addon_id", 100 ).primaryKey();
            table.string( "display_name", 200 );
            table.string( "version", 50 );
            table.string( "min_core_version", 50 );
            table.string( "max_core_version", 50 ).nullable();
            table.text( "contributes_to" ).nullable();
            table.boolean( "requires_ai" ).default( false );
            table.timestamp( "installed_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "last_seen_at" ).default( "CURRENT_TIMESTAMP" );
            table.boolean( "enabled" ).default( true );
            table.string( "enablement_mode", 20 ).default( "all" );
            table.boolean( "compatible" ).default( true );
            table.text( "compatibility_message" ).nullable();
            table.text( "metadata" ).nullable();

            table.index( "enabled" );
            table.index( "enablement_mode" );
        } );

        schema.create( "addon_organization_enablement", function( table ){
            table.string( "addon_id", 100 ).references( "addon_id" ).onTable( "addons" ).onDelete( "CASCADE" );
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.boolean( "enabled" ).default( true );
            table.timestamp( "enabled_at" ).default( "CURRENT_TIMESTAMP" );
            table.string( "enabled_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );

            table.primaryKey( [ "addon_id", "organization_id" ] );
            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "addon_organization_enablement" );
        schema.drop( "addons" );
    }

}
