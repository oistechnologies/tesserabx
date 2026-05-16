/**
 * Create app_settings: admin-editable runtime configuration.
 *
 * One row per setting key. value is stored as text and the value_type
 * column lets the service cast it back to the right primitive on
 * read (string | integer | boolean). The structure stays simple
 * because the set of keys is curated in code, not user-extensible.
 *
 * Branding keys live under "brand.*" and email-server overrides
 * live under "mail.*". Anything absent from this table falls back
 * to .env defaults so an unconfigured admin surface still works.
 */
component {

    function up( schema, qb ){
        schema.create( "app_settings", function( table ){
            table.string( "key", 100 ).primaryKey();
            table.text( "value" ).default( "" );
            table.string( "value_type", 20 ).default( "string" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
            table.string( "updated_by_agent_id", 36 ).nullable().references( "id" ).onTable( "agents" ).onDelete( "SET NULL" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "app_settings" );
    }

}
