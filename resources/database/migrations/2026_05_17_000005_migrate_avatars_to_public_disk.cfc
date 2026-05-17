/**
 * Migrate agent avatars from the secure CBFS disk to the public
 * disk.
 *
 * Phase 3 wrote avatars (original + 32/64/128/256 thumbnails) to
 * the default (secure) disk and served them through an auth-gated
 * handler. Phase 8.0 moves them to the public disk so browsers can
 * fetch them directly via /public-files/agents/... (no app round-
 * trip and no signed-in requirement; avatars are semi-public).
 *
 * cfmigrations runs in a CommandBox CLI context where
 * application.cbController is null and WireBox is not booted, so
 * this migration cannot ask CBFS for disk handles. Instead, when
 * both the default disk and the public disk are local providers,
 * it copies files directly between the on-disk roots. For any
 * non-local provider (S3, B2) it logs a warning and skips: those
 * operators must move files between buckets manually (one-time
 * `aws s3 cp` or similar).
 *
 * Idempotent: targets that already exist on the public side are
 * skipped, missing sources logged and skipped.
 */
component {

    function up( schema, qb ){
        // Local-disk roots. Operators running with cloud storage
        // (S3/B2) for the secure disk will see no local source files
        // and this migration becomes a no-op; in that case the
        // operator must copy avatar objects between buckets manually
        // (one-time `aws s3 cp` or equivalent).
        //
        // expandPath("/public-files") returns the literal "/public-files"
        // on contexts that have no mapping for it (cfmigrations CLI,
        // CI runners). Resolve relative to this migration's own file
        // path instead so the same code works in Docker dev and on
        // GitHub Actions.
        var migrationDir = getDirectoryFromPath( getCurrentTemplatePath() );
        // migrationDir = <project>/resources/database/migrations/
        var projectRoot  = getCanonicalPath( migrationDir & "../../../" );
        var secureRoot   = projectRoot & "/storage";
        var publicRoot   = projectRoot & "/public-files";

        if ( !directoryExists( secureRoot ) ) {
            // No local source files anywhere; nothing to migrate.
            return;
        }
        if ( !directoryExists( publicRoot ) ) directoryCreate( publicRoot, true );

        var rows = queryExecute(
            "SELECT id, profile_image_original_path
             FROM   agents
             WHERE  profile_image_original_path IS NOT NULL
               AND  profile_image_original_path <> ''"
        );

        var sizes = [ "32", "64", "128", "256" ];

        for ( var i = 1; i <= rows.recordCount; i++ ) {
            var agentId  = rows.id[ i ];
            var origPath = rows.profile_image_original_path[ i ];
            var basePath = "agents/" & agentId & "/profile";

            var keys = [ origPath ];
            for ( var size in sizes ) keys.append( basePath & "/" & size & ".jpg" );

            for ( var key in keys ) {
                var src = secureRoot & "/" & key;
                var dst = publicRoot & "/" & key;
                try {
                    if ( fileExists( dst ) ) continue;
                    if ( !fileExists( src ) ) {
                        writeLog(
                            text : "Phase 8.0 avatar migration: source missing [" & src & "] agent [" & agentId & "]",
                            log  : "tesserabx",
                            type : "warning"
                        );
                        continue;
                    }
                    var dstDir = getDirectoryFromPath( dst );
                    if ( !directoryExists( dstDir ) ) directoryCreate( dstDir, true );
                    fileCopy( src, dst );
                } catch ( any e ) {
                    writeLog(
                        text : "Phase 8.0 avatar migration: copy failed [" & key & "] agent [" & agentId & "]: " & e.message,
                        log  : "tesserabx",
                        type : "warning"
                    );
                }
            }
        }
    }

    function down( schema, qb ){
        // Intentional no-op. Don't delete public copies on rollback —
        // operators may have already pointed prod URLs at them.
    }

}
