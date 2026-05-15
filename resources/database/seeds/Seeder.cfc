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
        seedSlaCalendar( arguments.qb );
        seedSlaPolicy( arguments.qb );
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
            ensureOrganizationAdminRole( arguments.qb, existing.id );
            return;
        }
        var org = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        var contactId = createObject( "java", "java.util.UUID" ).randomUUID().toString();
        arguments.qb.newQuery().from( "contacts" ).insert( {
            "id"              : contactId,
            "organization_id" : org.id,
            "email"           : "client@example.com",
            "password_hash"   : variables.SEED_PASSWORD_HASH,
            "first_name"      : "Test",
            "last_name"       : "Client"
        } );
        ensureOrganizationAdminRole( arguments.qb, contactId );
    }

    /**
     * The migration 2026_05_15_000040 backfills "organization-admin"
     * for the legacy boolean. This guarantees the seed contact has
     * the role even on a fresh database where the migration runs
     * before any contact exists.
     */
    private void function ensureOrganizationAdminRole( required any qb, required string contactId ){
        var existing = arguments.qb.newQuery()
            .from( "contact_roles" )
            .where( "contact_id", arguments.contactId )
            .where( "role_key", "organization-admin" )
            .first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) return;
        arguments.qb.newQuery().from( "contact_roles" ).insert( {
            "id"         : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "contact_id" : arguments.contactId,
            "role_key"   : "organization-admin"
        } );
    }

    /**
     * Default Mon-Fri 9-5 UTC calendar with no holidays. Marked as
     * is_default so any policy without an explicit calendar uses it.
     */
    private void function seedSlaCalendar( required any qb ){
        var existing = arguments.qb.newQuery().from( "business_hours_calendars" ).where( "is_default", true ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) return;
        var weekly = serializeJSON( {
            "mon" : [ { "start" : "09:00", "end" : "17:00" } ],
            "tue" : [ { "start" : "09:00", "end" : "17:00" } ],
            "wed" : [ { "start" : "09:00", "end" : "17:00" } ],
            "thu" : [ { "start" : "09:00", "end" : "17:00" } ],
            "fri" : [ { "start" : "09:00", "end" : "17:00" } ],
            "sat" : [],
            "sun" : []
        } );
        arguments.qb.newQuery().from( "business_hours_calendars" ).insert( {
            "id"           : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "name"         : "Default 9-5",
            "timezone"     : "UTC",
            "weekly_hours" : weekly,
            "holidays"     : "[]",
            "is_default"   : true,
            "is_active"    : true
        } );
    }

    /**
     * Default catch-all policy: 60 minutes first response, 8 hours
     * resolution, attached to the default calendar. Tickets created
     * without a more specific match (by priority or tier) fall onto
     * this one.
     */
    private void function seedSlaPolicy( required any qb ){
        var existing = arguments.qb.newQuery().from( "sla_policies" ).where( "is_default", true ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) return;
        var cal = arguments.qb.newQuery().from( "business_hours_calendars" ).where( "is_default", true ).first();
        if ( isNull( cal ) || !structKeyExists( cal, "id" ) ) return;
        arguments.qb.newQuery().from( "sla_policies" ).insert( {
            "id"                         : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "name"                       : "Default policy",
            "first_response_minutes"     : 60,
            "resolution_minutes"         : 480,
            "business_hours_calendar_id" : cal.id,
            "precedence"                 : 0,
            "is_default"                 : true,
            "is_active"                  : true
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
