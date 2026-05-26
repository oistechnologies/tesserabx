/**
 * Create organization_branding: per-tenant overrides for the same
 * five brand keys that live globally in app_settings.
 *
 * Every column except organization_id is nullable. The composer's
 * BrandingService merges per-org rows over global settings
 * column-by-column: a non-null per-org value wins; a null falls
 * through to the global. This means an admin can override only the
 * pieces they want (e.g. a custom logo URL while keeping the global
 * product name).
 *
 * Tenant scope: organization_id is BOTH the primary key and the
 * foreign key to organizations. There is exactly one branding row
 * per organization. The row is automatically scoped to the
 * organization via the contacts module's TenantScope.
 */
component {

    function up( schema, qb ){
        schema.create( "organization_branding", function( table ){
            table.string( "organization_id", 36 )
                 .references( "id" ).onTable( "organizations" ).onDelete( "CASCADE" );
            table.string( "product_name", 200 ).nullable();
            table.string( "tagline",      400 ).nullable();
            table.text(   "logo_url"           ).nullable();
            table.string( "primary_color", 32  ).nullable();
            table.text(   "footer_text"        ).nullable();
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
            table.string( "updated_by_agent_id", 36 )
                 .nullable()
                 .references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
            // organization_id is both the FK and the PK so each
            // organization has at most one branding row. Declare
            // the PK separately because qb chains primaryKey()
            // and references() incorrectly when combined on one
            // column (it tries to back the PK with a phantom
            // "id" column).
            table.primaryKey( "organization_id" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "organization_branding" );
    }

}
