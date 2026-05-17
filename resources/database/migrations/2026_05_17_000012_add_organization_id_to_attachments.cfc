/**
 * Add organization_id to attachments.
 *
 * Two reasons:
 *
 *  1. Per-org CBFS prefixing: new uploads land at
 *     org/<orgId>/tickets/<ticketId>/<uuid>.<ext> on the secure
 *     disk. The Attachment row carries the org id so callers can
 *     construct the storage path without re-resolving through the
 *     parent ticket every time.
 *
 *  2. Defense-in-depth tenant queries: a future bug in the access
 *     check still can't accidentally return cross-org rows because
 *     callers can pass organization_id as a WHERE-clause filter.
 *
 * Nullable so accountless tickets (no contact, no org) still fit.
 * The up() backfills from each row's parent ticket.
 *
 * No tenant Quick global scope is attached to Attachment; access
 * control runs in the service layer so the route surface produces
 * a uniform 403.
 */
component {

    function up( schema, qb ){
        schema.alter( "attachments", function( table ){
            table.addColumn( table.string( "organization_id", 36 ).nullable() );
        } );
        queryExecute(
            "ALTER TABLE attachments
             ADD CONSTRAINT fk_attachments_organization_id
             FOREIGN KEY ( organization_id ) REFERENCES organizations ( id )
             ON DELETE SET NULL"
        );
        // Backfill from each attachment's parent ticket.
        queryExecute(
            "UPDATE attachments a
             SET    organization_id = t.organization_id
             FROM   tickets t
             WHERE  a.ticket_id = t.id
               AND  a.organization_id IS NULL"
        );
        queryExecute(
            "CREATE INDEX idx_attachments_org_created ON attachments ( organization_id, created_at )"
        );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_attachments_org_created" );
        queryExecute( "ALTER TABLE attachments DROP CONSTRAINT IF EXISTS fk_attachments_organization_id" );
        schema.alter( "attachments", function( table ){
            table.dropColumn( "organization_id" );
        } );
    }

}
