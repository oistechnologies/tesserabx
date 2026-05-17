/**
 * Add the human-profile columns to agents.
 *
 * Title, hire_date, and termination_date are HR-style fields. Title
 * and department are admin-only at the application layer (set on the
 * admin agent form; not editable from My Account).
 *
 * employee_id has a unique index, but is nullable. Postgres treats
 * NULL as distinct in unique indexes, so any number of agents can
 * have a null employee_id; only non-null values must be unique.
 *
 * Indexes added in this migration:
 *   - department (powers the admin list filter dropdown)
 *   - (last_name, first_name) composite (admin list sort)
 *   - hire_date (admin list sort)
 *   - employee_id unique
 */
component {

    function up( schema, qb ){
        schema.alter( "agents", function( table ){
            table.addColumn( table.string( "title", 150 ).nullable() );
            table.addColumn( table.date( "hire_date" ).nullable() );
            table.addColumn( table.date( "termination_date" ).nullable() );
            table.addColumn( table.string( "phone_work", 50 ).nullable() );
            table.addColumn( table.string( "phone_mobile", 50 ).nullable() );
            table.addColumn( table.string( "department", 150 ).nullable() );
            table.addColumn( table.string( "employee_id", 100 ).nullable() );
            table.addColumn( table.text( "bio" ).nullable() );
            table.addColumn( table.text( "email_signature" ).nullable() );
            table.addColumn( table.string( "slack_handle", 100 ).nullable() );
            table.addColumn( table.string( "teams_handle", 100 ).nullable() );
        } );

        queryExecute( "CREATE INDEX idx_agents_department ON agents ( department )" );
        queryExecute( "CREATE INDEX idx_agents_name ON agents ( last_name, first_name )" );
        queryExecute( "CREATE INDEX idx_agents_hire_date ON agents ( hire_date )" );
        queryExecute( "CREATE UNIQUE INDEX idx_agents_employee_id ON agents ( employee_id )" );
    }

    function down( schema, qb ){
        queryExecute( "DROP INDEX IF EXISTS idx_agents_employee_id" );
        queryExecute( "DROP INDEX IF EXISTS idx_agents_hire_date" );
        queryExecute( "DROP INDEX IF EXISTS idx_agents_name" );
        queryExecute( "DROP INDEX IF EXISTS idx_agents_department" );

        schema.alter( "agents", function( table ){
            table.dropColumn( "teams_handle" );
            table.dropColumn( "slack_handle" );
            table.dropColumn( "email_signature" );
            table.dropColumn( "bio" );
            table.dropColumn( "employee_id" );
            table.dropColumn( "department" );
            table.dropColumn( "phone_mobile" );
            table.dropColumn( "phone_work" );
            table.dropColumn( "termination_date" );
            table.dropColumn( "hire_date" );
            table.dropColumn( "title" );
        } );
    }

}
