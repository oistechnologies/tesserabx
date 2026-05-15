/**
 * Add attach_file flag to scheduled_exports.
 *
 * When true, the scheduler attaches the generated CSV to the
 * "export ready" email. When false (default), the email just
 * tells the recipient the file is ready and points them at the
 * admin download. We default to false because attaching large
 * exports can blow past mailbox limits; opting in keeps that an
 * explicit admin choice.
 */
component {

    function up( schema, qb ){
        queryExecute(
            "ALTER TABLE scheduled_exports ADD COLUMN attach_file BOOLEAN NOT NULL DEFAULT FALSE"
        );
    }

    function down( schema, qb ){
        queryExecute( "ALTER TABLE scheduled_exports DROP COLUMN IF EXISTS attach_file" );
    }

}
