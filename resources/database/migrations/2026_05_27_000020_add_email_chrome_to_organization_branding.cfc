/**
 * Add per-organization email chrome style override.
 *
 * The composer now ships "notification" chrome (full header band,
 * logo, footer) as the default for every outbound. Organizations
 * that prefer the thin person-to-person "reply" chrome opt in by
 * setting this column to 'reply'. NULL or 'notification' (the
 * default) keeps the full chrome.
 *
 * Kept as a free-form short string rather than a boolean so a
 * future third chrome style does not need a schema change.
 */
component {

    function up( schema, qb ){
        schema.alter( "organization_branding", function( table ){
            table.addColumn( table.string( "email_chrome", 20 ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "organization_branding", function( table ){
            table.dropColumn( "email_chrome" );
        } );
    }

}
