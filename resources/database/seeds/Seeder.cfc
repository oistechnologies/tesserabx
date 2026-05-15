/**
 * Dev seeder.
 *
 * Phase 0: one organization, one client contact, one admin agent.
 * Enough to verify both surfaces' authentication flows end to end.
 *
 * Invoke: box migrate seed run
 *
 * Idempotent: running it twice does not error or duplicate data.
 *
 * The cfmigrations CLI runs this in the CommandBox shell (CFML/Lucee),
 * not the BoxLang application runtime, so we cannot use the BCrypt
 * module (it's loaded by cbjavaloader inside the app, not here). The
 * password "password" is seeded with a known-stable bcrypt-10 hash that
 * the running cbauth verifies normally at login time. Real users get
 * real passwords; this seeder is dev convenience only.
 */
component {

    // bcrypt-12 hash of "password", verified against the running app's
    // BCrypt service. Both test users share this. Real users get real
    // password hashes; this is dev-seeding convenience only.
    variables.SEED_PASSWORD_HASH = "$2a$12$G7WvY1Y4gl0sGJCWBiuWSemOi.dlpUXywSgk6JpT0QJ2AnP70mP8C";

    function run( qb, mockdata ){
        seedOrganization( arguments.qb );
        seedContact( arguments.qb );
        seedAgent( arguments.qb );
    }

    private void function seedOrganization( required any qb ){
        var existing = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) {
            return;
        }
        arguments.qb.newQuery().from( "organizations" ).insert( {
            "id"   : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "name" : "Acme Corp",
            "slug" : "acme"
        } );
    }

    private void function seedContact( required any qb ){
        var existing = arguments.qb.newQuery().from( "contacts" ).where( "email", "client@example.com" ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) {
            return;
        }
        var org = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        arguments.qb.newQuery().from( "contacts" ).insert( {
            "id"                    : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "organization_id"       : org.id,
            "email"                 : "client@example.com",
            "password_hash"         : variables.SEED_PASSWORD_HASH,
            "first_name"            : "Test",
            "last_name"             : "Client",
            "is_organization_admin" : true
        } );
    }

    private void function seedAgent( required any qb ){
        var existing = arguments.qb.newQuery().from( "agents" ).where( "email", "agent@example.com" ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) {
            return;
        }
        arguments.qb.newQuery().from( "agents" ).insert( {
            "id"            : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "email"         : "agent@example.com",
            "password_hash" : variables.SEED_PASSWORD_HASH,
            "first_name"    : "Test",
            "last_name"     : "Agent",
            "is_admin"      : true
        } );
    }

}
