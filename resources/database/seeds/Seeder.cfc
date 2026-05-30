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
        seedOffices( arguments.qb );
        seedContact( arguments.qb );
        seedAgent( arguments.qb );
        seedDomains( arguments.qb );
        linkPrimaryContact( arguments.qb );
        seedSlaCalendar( arguments.qb );
        seedSlaPolicy( arguments.qb );
    }

    private void function seedOrganization( required any qb ){
        var existing = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) {
            // Re-seeding an older dev database: turn on the demo
            // attributes (and auto-provisioning) so the new feature is
            // visible without a fresh DB.
            arguments.qb.newQuery().from( "organizations" ).where( "id", existing.id ).update( {
                "status"                  : "active",
                "tier"                    : "Gold",
                "website"                 : "https://acme.example.com",
                "timezone"                : "America/New_York",
                "auto_provision_contacts" : true
            } );
            return;
        }
        arguments.qb.newQuery().from( "organizations" ).insert( {
            "id"                      : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "name"                    : "Acme Corp",
            "slug"                    : "acme",
            "status"                  : "active",
            "tier"                    : "Gold",
            "website"                 : "https://acme.example.com",
            "timezone"                : "America/New_York",
            "auto_provision_contacts" : true
        } );
    }

    /**
     * A primary HQ office and one branch for Acme, so the office UI and
     * contact-to-office assignment have data to work with.
     */
    private void function seedOffices( required any qb ){
        var org = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        if ( isNull( org ) || !structKeyExists( org, "id" ) ) return;
        var existing = arguments.qb.newQuery().from( "offices" ).where( "organization_id", org.id ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) return;
        arguments.qb.newQuery().from( "offices" ).insert( {
            "id"              : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "organization_id" : org.id,
            "name"            : "Headquarters",
            "address_line1"   : "100 Market Street",
            "city"            : "New York",
            "region"          : "NY",
            "postal_code"     : "10001",
            "country"         : "US",
            "phone"           : "+1-212-555-0100",
            "timezone"        : "America/New_York",
            "is_primary"      : true
        } );
        arguments.qb.newQuery().from( "offices" ).insert( {
            "id"              : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "organization_id" : org.id,
            "name"            : "West Coast Branch",
            "address_line1"   : "555 Pine Avenue",
            "city"            : "San Francisco",
            "region"          : "CA",
            "postal_code"     : "94104",
            "country"         : "US",
            "phone"           : "+1-415-555-0150",
            "timezone"        : "America/Los_Angeles",
            "is_primary"      : false
        } );
    }

    /**
     * The acme.com domain, verified, so an inbound email from a never-
     * seen acme.com sender auto-creates a contact (Acme has
     * auto_provision_contacts on).
     */
    private void function seedDomains( required any qb ){
        var org = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        if ( isNull( org ) || !structKeyExists( org, "id" ) ) return;
        var existing = arguments.qb.newQuery().from( "organization_domains" ).where( "domain", "acme.com" ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) return;
        arguments.qb.newQuery().from( "organization_domains" ).insert( {
            "id"              : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "organization_id" : org.id,
            "domain"          : "acme.com",
            "is_verified"     : true
        } );
    }

    /**
     * Point Acme's primary_contact_id at the seeded client contact,
     * once both exist. Idempotent: only sets it when currently empty.
     */
    private void function linkPrimaryContact( required any qb ){
        var org = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        if ( isNull( org ) || !structKeyExists( org, "id" ) ) return;
        if ( !isNull( org.primary_contact_id ?: "" ) && len( org.primary_contact_id ?: "" ) ) return;
        var contact = arguments.qb.newQuery().from( "contacts" ).where( "email", "client@example.com" ).first();
        if ( isNull( contact ) || !structKeyExists( contact, "id" ) ) return;
        arguments.qb.newQuery().from( "organizations" ).where( "id", org.id ).update( {
            "primary_contact_id" : contact.id
        } );
    }

    private void function seedContact( required any qb ){
        var hqOffice = "";
        var org = arguments.qb.newQuery().from( "organizations" ).where( "slug", "acme" ).first();
        if ( !isNull( org ) && structKeyExists( org, "id" ) ) {
            var office = arguments.qb.newQuery().from( "offices" )
                .where( "organization_id", org.id ).where( "is_primary", true ).first();
            if ( !isNull( office ) && structKeyExists( office, "id" ) ) hqOffice = office.id;
        }

        var existing = arguments.qb.newQuery().from( "contacts" ).where( "email", "client@example.com" ).first();
        if ( !isNull( existing ) && structKeyExists( existing, "id" ) ) {
            // Assign the seed contact to HQ if it has no office yet.
            if ( len( hqOffice ) && ( isNull( existing.office_id ?: "" ) || !len( existing.office_id ?: "" ) ) ) {
                arguments.qb.newQuery().from( "contacts" ).where( "id", existing.id ).update( { "office_id" : hqOffice } );
            }
            ensureOrganizationAdminRole( arguments.qb, existing.id );
            return;
        }
        var contactId = createObject( "java", "java.util.UUID" ).randomUUID().toString();
        var row = {
            "id"              : contactId,
            "organization_id" : org.id,
            "email"           : "client@example.com",
            "password_hash"   : variables.SEED_PASSWORD_HASH,
            "first_name"      : "Test",
            "last_name"       : "Client",
            "job_title"       : "IT Manager",
            "phone"           : "+1-212-555-0123",
            "timezone"        : "America/New_York",
            "source"          : "agent"
        };
        if ( len( hqOffice ) ) row[ "office_id" ] = hqOffice;
        arguments.qb.newQuery().from( "contacts" ).insert( row );
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
