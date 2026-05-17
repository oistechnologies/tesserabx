/**
 * Soft-delete columns on attachments.
 *
 * Phase 8 lets agents delete attachments without losing the audit
 * trail. The bytes stay in CBFS, the metadata stays in this table,
 * but reads are gated on deleted_at being null for any viewer who
 * shouldn't see deleted history (contacts get a 403; agents see
 * the row with a "deleted" badge). Deletion reason is required at
 * the service layer.
 *
 * deleted_by_agent_id is nullable + ON DELETE SET NULL so an agent
 * leaving the company doesn't cascade-blank the deletion record.
 */
component {

    function up( schema, qb ){
        schema.alter( "attachments", function( table ){
            table.addColumn( table.timestamp( "deleted_at" ).nullable() );
            table.addColumn( table.string( "deleted_by_agent_id", 36 ).nullable() );
            table.addColumn( table.text( "deletion_reason" ).nullable() );
        } );
        queryExecute(
            "ALTER TABLE attachments
             ADD CONSTRAINT fk_attachments_deleted_by_agent_id
             FOREIGN KEY ( deleted_by_agent_id ) REFERENCES agents ( id )
             ON DELETE SET NULL"
        );
        queryExecute( "CREATE INDEX idx_attachments_deleted_at ON attachments ( deleted_at )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_attachments_deleted_at" );
        queryExecute( "ALTER TABLE attachments DROP CONSTRAINT IF EXISTS fk_attachments_deleted_by_agent_id" );
        schema.alter( "attachments", function( table ){
            table.dropColumn( "deletion_reason" );
            table.dropColumn( "deleted_by_agent_id" );
            table.dropColumn( "deleted_at" );
        } );
    }

}
