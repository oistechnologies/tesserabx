/**
 * Create audit_events: the central cross-module audit log.
 *
 * Every significant operation (role grants, contact merges, ticket
 * lifecycle events, SLA policy changes, article deletions, etc.)
 * is recorded here through AuditService@audit. The event_type uses
 * dotted notation ("contact.role_granted", "ticket.status_changed")
 * so the table is extensible without schema migrations.
 *
 * Not tenant-scoped at the entity level. The organization_id column
 * is captured for events that have one so the admin UI can filter
 * by tenant when desired; events with no tenant (system tasks,
 * cross-tenant operations) leave it null.
 *
 * Distinct from any module's own domain history (tickets owns
 * ticket_events for the agent-facing timeline; this is the
 * cross-cutting compliance log).
 */
component {

    function up( schema, qb ){
        schema.create( "audit_events", function( table ){
            table.string( "id", 36 ).primaryKey();
            table.string( "event_type", 100 );
            table.string( "entity_type", 100 ).nullable();
            table.string( "entity_id", 36 ).nullable();
            // No FK to organizations. The audit log is append-only
            // and must survive entity deletion (compliance), so the
            // organization_id is a best-effort reference rather than
            // a referential-integrity constraint.
            table.string( "organization_id", 36 ).nullable();
            table.string( "actor_type", 50 ).nullable();
            table.string( "actor_id", 36 ).nullable();
            // metadata_json (not metadata) avoids a collision between
            // the auto-generated `getMetadata()` accessor on the
            // entity and BoxLang's built-in `getMetadata(obj)` BIF.
            table.text( "metadata_json" ).nullable();
            table.timestamp( "occurred_at" ).default( "CURRENT_TIMESTAMP" );

            table.index( "event_type" );
            table.index( [ "entity_type", "entity_id" ], "idx_audit_entity" );
            table.index( "organization_id" );
            table.index( [ "actor_type", "actor_id" ], "idx_audit_actor" );
            table.index( "occurred_at" );
        } );
    }

    function down( schema, qb ){
        schema.drop( "audit_events" );
    }

}
