/**
 * PostgresDBProvider: cbq DBProvider override for Postgres.
 *
 * Two Postgres compat issues in the shipped cbq DBProvider
 * prevented the worker from draining the queue in our BoxLang
 * stack:
 *
 *   1. Raw SQL fragments reference camelCase columns unquoted,
 *      Postgres folds them to lowercase, no match → "column
 *      reservedby does not exist". Fixed by quoting every
 *      identifier in the rewritten SQL below.
 *
 *   2. qb's typed bindings do NOT round-trip through BoxLang's
 *      queryExecute as JDBC types; numeric values bound to
 *      bigint columns arrive as varchar and Postgres rejects
 *      with "column X is of type bigint but expression is of
 *      type character varying". `cast( ? as bigint )` doesn't
 *      help — the binding still goes in as varchar and the
 *      planner has nothing to cast yet. Fixed by inlining the
 *      bigint values as SQL literals (epoch seconds are
 *      validated through int() before interpolation so this is
 *      not an injection vector).
 *
 * Hot paths only: fetchPotentiallyOpenRecords and
 * tryToLockRecords. The per-job update methods only fire after
 * a job is reserved and they UPDATE bigint columns rather than
 * compare against them; if those break in practice the same
 * pattern applies.
 *
 * .cfc, not .bx, because cbq's parent uses arrow-closure
 * lambdas and the BoxLang `bx-compat-cfml` private-method
 * override behavior is more reliable through the cfc compiler
 * path.
 */
component extends="cbq.models.Providers.DBProvider" {

	/**
	 * Find ids that can be locked. Raw SQL with inlined bigint
	 * literals; identifiers double-quoted to preserve camelCase.
	 */
	private array function fetchPotentiallyOpenRecords( required numeric capacity, required WorkerPool pool ) {
		if ( log.canDebug() ) {
			log.debug( "Fetching up to #capacity# potentially open record(s) [Worker Pool #pool.getUniqueId()#]." );
		}

		var nowUnix   = int( variables.getCurrentUnixTimestamp() );
		var staleUnix = int( nowUnix - arguments.pool.getTimeout() );

		// Build the queue IN-clause from the pool's queue list.
		// Order of binds MUST match the order placeholders appear
		// in the SQL: queue IN (?, ?...) comes BEFORE the ORDER
		// BY CASE WHEN reservedBy = ? clause, so queue binds go
		// first and the uniqueId bind goes last.
		var queueClause = "";
		var binds = [];
		if ( !shouldWorkAllQueues( arguments.pool ) ) {
			var placeholders = [];
			for ( var q in arguments.pool.getQueue() ) {
				placeholders.append( "?" );
				binds.append( { value: q, cfsqltype: "VARCHAR" } );
			}
			queueClause = " AND queue IN ( " & placeholders.toList( "," ) & " )";
		}
		binds.append( { value: arguments.pool.getUniqueId(), cfsqltype: "VARCHAR" } );

		// Bigint values are inlined as integer literals; pool
		// uniqueid + queue names go through the parameter list
		// because they're free-form strings.
		var sql = "
			SELECT id
			FROM   " & variables.tableName & "
			WHERE  ""completedDate"" IS NULL
			AND    ""failedDate""    IS NULL
			" & queueClause & "
			AND    (
			           ( ""reservedDate"" IS NULL
			             AND ""reservedBy"" IS NULL
			             AND ""availableDate"" <= " & nowUnix & " )
			        OR ( ""reservedDate"" <= " & staleUnix & " )
			        OR ( ""reservedDate"" IS NULL
			             AND ""reservedBy"" IS NOT NULL
			             AND ""availableDate"" <= " & nowUnix & " )
			       )
			ORDER BY CASE WHEN ""reservedBy"" = ? THEN 1 ELSE 2 END ASC,
			         id ASC
			LIMIT  " & int( arguments.capacity ) & "
			FOR UPDATE SKIP LOCKED
		";

		var result = queryExecute( sql, binds, variables.defaultQueryOptions );
		var ids = [];
		for ( var i = 1; i <= result.recordCount; i++ ) {
			ids.append( result.id[ i ] );
		}

		if ( log.canDebug() ) {
			log.debug(
				"Found #arrayLen( ids )# potentially open record(s) to lock [Worker Pool #pool.getUniqueId()#].",
				{ "ids" : ids }
			);
		}

		return ids;
	}

	/**
	 * Lock the ids fetched above. Same pattern: literal bigint
	 * comparison, quoted identifiers, varchar ids through bindings.
	 */
	private void function tryToLockRecords( required array ids, required any pool ) {
		if ( !arrayLen( arguments.ids ) ) return;
		if ( log.canDebug() ) {
			log.debug(
				"Attempting to lock #arrayLen( ids )# record(s) for Worker Pool #pool.getUniqueId()#.",
				{ "ids" : arguments.ids }
			);
		}

		var staleUnix = int( variables.getCurrentUnixTimestamp() - arguments.pool.getTimeout() );
		// cbq_jobs.id is bigint. BoxLang's queryExecute binds
		// values as varchar (even with cfsqltype hints), and
		// Postgres rejects bigint = varchar. Validate the
		// incoming ids as ints and inline them; uniqueId stays
		// as a bound varchar.
		var idLiterals = [];
		for ( var id in arguments.ids ) {
			if ( !isNumeric( id ) ) continue;
			idLiterals.append( int( id ) );
		}
		if ( !idLiterals.len() ) return;

		var binds = [
			{ value: arguments.pool.getUniqueId(), cfsqltype: "VARCHAR" }
		];
		var sql = "
			UPDATE " & variables.tableName & "
			SET    ""reservedBy""   = ?,
			       ""reservedDate"" = NULL
			WHERE  id IN ( " & idLiterals.toList( "," ) & " )
			AND    ""completedDate"" IS NULL
			AND    ""failedDate""    IS NULL
			AND    (
			           ( ""reservedBy"" IS NULL AND ""reservedDate"" IS NULL )
			        OR ( ""reservedDate"" <= " & staleUnix & " )
			       )
		";

		queryExecute( sql, binds, variables.defaultQueryOptions );

		if ( log.canDebug() ) {
			log.debug( "Locked candidates for Worker Pool #pool.getUniqueId()#." );
		}
	}

}
