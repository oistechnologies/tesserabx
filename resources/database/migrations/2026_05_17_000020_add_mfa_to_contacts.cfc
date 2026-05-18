/**
 * Add TOTP MFA columns to contacts.
 *
 * Mirrors the agent-side MFA columns from
 * 2026_05_16_000020_add_mfa_to_agents.cfc. The fields and their
 * semantics are intentionally identical so TotpService@agent can
 * verify a contact's code without caring which table the secret
 * came from.
 *
 * - mfa_secret: the base32-encoded RFC 6238 shared secret. Stored
 *   plaintext because HMAC needs it on every login; no one-way
 *   hash works. DB-level access is the trust boundary.
 * - mfa_enabled: true after the contact confirms a code at
 *   enrollment time. Defaults false; client MFA is opt-in (per
 *   the build plan, MFA is required for provider agents and
 *   optional for client users).
 * - mfa_enrolled_at: when the secret was first confirmed.
 * - mfa_recovery_codes: a JSONB array of bcrypt-hashed one-time
 *   recovery codes. Each one is consumed (set to "") on use.
 *
 * Existing contacts come in with NULL/false; the portal session
 * handler treats them as password-only until they opt in from
 * the My Account page.
 */
component {

    function up( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.addColumn( table.string( "mfa_secret", 100 ).nullable() );
            table.addColumn( table.boolean( "mfa_enabled" ).default( false ) );
            table.addColumn( table.timestamp( "mfa_enrolled_at" ).nullable() );
            table.addColumn( table.json( "mfa_recovery_codes" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "contacts", function( table ){
            table.dropColumn( "mfa_recovery_codes" );
            table.dropColumn( "mfa_enrolled_at" );
            table.dropColumn( "mfa_enabled" );
            table.dropColumn( "mfa_secret" );
        } );
    }

}
