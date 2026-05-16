/**
 * Add TOTP MFA columns to agents.
 *
 * - mfa_secret: the base32-encoded RFC 6238 shared secret. Stored
 *   in plaintext because we need to compute HMAC on every login;
 *   no one-way hash works here. DB-level access is the trust
 *   boundary.
 * - mfa_enabled: true after the agent confirms a code at
 *   enrollment time. False on freshly-seeded accounts and on
 *   accounts an admin has reset.
 * - mfa_enrolled_at: when the secret was first confirmed.
 * - mfa_recovery_codes: a JSONB array of bcrypt-hashed one-time
 *   recovery codes. Each one is consumed (set to "") on use.
 *
 * Existing agents come in with NULL/false; the session handler
 * redirects them to enrollment on next login.
 */
component {

    function up( schema, qb ){
        schema.alter( "agents", function( table ){
            table.addColumn( table.string( "mfa_secret", 100 ).nullable() );
            table.addColumn( table.boolean( "mfa_enabled" ).default( false ) );
            table.addColumn( table.timestamp( "mfa_enrolled_at" ).nullable() );
            table.addColumn( table.json( "mfa_recovery_codes" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "agents", function( table ){
            table.dropColumn( "mfa_recovery_codes" );
            table.dropColumn( "mfa_enrolled_at" );
            table.dropColumn( "mfa_enabled" );
            table.dropColumn( "mfa_secret" );
        } );
    }

}
