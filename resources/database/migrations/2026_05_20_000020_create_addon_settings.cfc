/**
 * Create addon_settings: per-tenant configuration overrides for add-ons.
 *
 * An add-on declares its settings schema (key, type, label, default,
 * secret, perTenant) in its `ModuleConfig.bx` manifest via
 * `settings.tesserabx.settings = [...]`. The declared default is the
 * global value; this table stores per-organization overrides only.
 *
 * Resolution rule (implemented in SettingsRegistry.resolve):
 *   1. Look up an override in this table for (addon_id, organization_id, setting_key).
 *   2. If absent, return the default declared in the manifest.
 *   3. If the manifest does not declare the key either, return null.
 *
 * Global "change-the-default" overrides without a per-tenant scope
 * are not supported by this table; bump the manifest itself or set
 * the override for each tenant explicitly. Per-tenant settings
 * declared as perTenant=false in the manifest reject any insert
 * attempt in SettingsRegistry.set.
 */
component {

    function up( schema, qb ){
        schema.create( "addon_settings", function( table ){
            table.string( "addon_id", 100 ).references( "addon_id" ).onTable( "addons" ).onDelete( "CASCADE" );
            table.string( "organization_id", 36 ).references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.string( "setting_key", 200 );
            table.text( "value" ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
            table.string( "updated_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );

            table.primaryKey( [ "addon_id", "organization_id", "setting_key" ] );
            table.index( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "addon_settings" );
    }

}
