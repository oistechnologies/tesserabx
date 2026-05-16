/**
 * PostgresDBProvider: cbq DBProvider override for Postgres.
 *
 * The shipped cbq.models.Providers.DBProvider issues raw SQL
 * fragments like `orderByRaw( "CASE WHEN reservedBy = ?..." )`
 * with unquoted camelCase identifiers. Postgres folds those to
 * lowercase, but the column was created (via qb's quoted DDL) as
 * `reservedBy` — so the worker's reservation query fails with
 * `column "reservedby" does not exist` and the queue never drains.
 *
 * This override copies the affected `fetchPotentiallyOpenRecords`
 * (the only spot the bug surfaces in practice — the other two
 * orderByRaw uses route through generateQueuePriorityOrderBy
 * which only references `queue`, lowercase, safe). The literal
 * `reservedBy` in the raw fragment is wrapped in double quotes so
 * Postgres preserves case and matches the actual column.
 *
 * The file is .cfc (not .bx) because cbq's parent uses
 * arrow-closure lambdas and bx-compat-cfml inheritance with
 * private-method overrides is most reliable through the cfc
 * compiler path.
 */
component extends="cbq.models.Providers.DBProvider" {

	private array function fetchPotentiallyOpenRecords( required numeric capacity, required WorkerPool pool ) {
		if ( log.canDebug() ) {
			log.debug( "Fetching up to #capacity# potentially open record(s) [Worker Pool #pool.getUniqueId()#]." );
		}

		var ids = newQuery()
			.from( variables.tableName )
			.limit( arguments.capacity )
			.lockForUpdate( skipLocked = true )
			.when( !shouldWorkAllQueues( arguments.pool ), ( q ) => q.whereIn( "queue", pool.getQueue() ) )
			.where( ( q ) => {
				q.whereNull( "completedDate" );
				q.whereNull( "failedDate" );
			} )
			.where( ( q1 ) => {
				q1.where( ( q2 ) => {
					q2.whereNull( "reservedDate" )
						.whereNull( "reservedBy" )
						.where(
							"availableDate",
							"<=",
							variables.getCurrentUnixTimestamp()
						);
				} );
				q1.orWhere(
					"reservedDate",
					"<=",
					variables.getCurrentUnixTimestamp() - pool.getTimeout()
				);
				q1.orWhere( ( q3 ) => {
					q3.whereNull( "reservedDate" )
						.whereNotNull( "reservedBy" )
						.where(
							"availableDate",
							"<=",
							variables.getCurrentUnixTimestamp()
						);
				} );
			} )
			// Identifier is double-quoted so Postgres preserves the
			// camelCase the column was created under. The upstream
			// fragment uses the bare name and folds to lowercase.
			.orderByRaw( "CASE WHEN ""reservedBy"" = ? THEN 1 ELSE 2 END ASC", [ arguments.pool.getUniqueId() ] )
			.when( worksMultipleQueues( arguments.pool ), ( q ) => {
				q.orderByRaw( generateQueuePriorityOrderBy( pool ) )
			} )
			.orderByAsc( "id" )
			.values( column = "id", options = variables.defaultQueryOptions );

		if ( log.canDebug() ) {
			log.debug(
				"Found #arrayLen( ids )# potentially open record(s) to lock [Worker Pool #pool.getUniqueId()#].",
				{ "ids" : ids }
			);
		}

		return ids;
	}

}
