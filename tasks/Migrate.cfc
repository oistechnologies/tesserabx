/**
 * Migrate: CommandBox task wrapping cfmigrations with per-add-on
 * discovery.
 *
 * Usage:
 *   box task run tasks/Migrate up
 *   box task run tasks/Migrate down
 *   box task run tasks/Migrate status
 *   box task run tasks/Migrate fresh
 *   box task run tasks/Migrate reset
 *   box task run tasks/Migrate install
 *   box task run tasks/Migrate uninstall
 *   box task run tasks/Migrate stage    (stage only, do not run)
 *
 * Why this exists:
 *   cfmigrations' `migrationsDirectory` is single-valued and the CLI
 *   reads `.cfmigrations.json` which has no multi-directory option.
 *   This task discovers migration files shipped inside add-on modules
 *   and stages them into the single central directory so the standard
 *   cfmigrations runner picks them up.
 *
 * Discovery sources:
 *   - modules/<slug>/migrations/                    (ForgeBox install path)
 *   - modules/<slug>/resources/migrations/
 *   - modules_app/<slug>/migrations/                (first-party split-outs)
 *   - modules_app/<slug>/resources/migrations/
 *   - sample-addons/<slug>/migrations/              (in-tree sample add-ons)
 *
 * Staging convention:
 *   Each discovered file is copied into
 *   resources/database/migrations/_addon_<slug>_<originalFilename>.cfc.
 *   The `_addon_` prefix is the canonical marker:
 *     - gitignore filters it so staged copies stay out of version
 *       control (the source-of-truth is the file in the add-on tree)
 *     - cfmigrations sees a distinct component name per add-on so two
 *       add-ons declaring the same timestamped filename do not collide
 *   The timestamp embedded in the original filename is preserved and
 *   drives cfmigrations sort order.
 *
 * Idempotency:
 *   Subsequent stage calls compare hashes; unchanged files are not
 *   re-copied. The staging report is written to
 *   resources/database/migrations/.staged.json so the operator can
 *   audit what came from where.
 *
 * Why .cfc, not .bx:
 *   CommandBox 6.x runs on Lucee and hardcodes .cfc for task runners
 *   (see tasks/ScaffoldAddon.cfc for the same note).
 */
component extends="commandbox.system.BaseTask" {

    // The single directory cfmigrations scans. Relative to the project
    // root so the task works regardless of where CommandBox launched.
    variables.CENTRAL_DIR = "resources/database/migrations";

    // Add-on source roots to walk; each path is resolved against the
    // project root, then we look at every top-level subdirectory in
    // that root for a /migrations or /resources/migrations folder.
    variables.SOURCE_ROOTS = [ "modules", "modules_app", "sample-addons" ];

    /**
     * Default action when called with no subcommand. Stage-only, so
     * a typo never accidentally runs migrations.
     */
    function run(){ stage(); }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate up`.
     */
    function up(){        runWithStaging( "up" );        }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate down`.
     */
    function down(){      runWithStaging( "down" );      }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate fresh`.
     */
    function fresh(){     runWithStaging( "fresh" );     }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate refresh` (down + up).
     */
    function refresh(){   runWithStaging( "refresh" );   }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate reset`.
     */
    function reset(){     runWithStaging( "reset" );     }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate install`.
     */
    function install(){   runWithStaging( "install" );   }

    /**
     * Stage every add-on migration into the central directory, then
     * run `box migrate uninstall`.
     */
    function uninstall(){ runWithStaging( "uninstall" ); }

    /**
     * Stage only (dry run). Discover add-on migrations and copy them
     * into the central dir, then return without running anything.
     */
    function stage(){
        var report = stageAddonMigrations( resolveProjectRoot() );
        printStageReport( report );
        print.greenLine( "Stage complete. No migrations were run." ).toConsole();
    }

    private void function runWithStaging( required string subcommand ){
        var report = stageAddonMigrations( resolveProjectRoot() );
        printStageReport( report );
        print.line( "" ).toConsole();
        print.cyanLine( "Running: box migrate " & arguments.subcommand ).toConsole();
        command( "migrate " & arguments.subcommand ).run();
    }

    private string function resolveProjectRoot(){
        var projectRoot = getCWD();
        if ( right( projectRoot, 1 ) != "/" ) projectRoot &= "/";
        return projectRoot;
    }

    // ----------------------------------------------------------------
    //  Staging
    // ----------------------------------------------------------------

    private struct function stageAddonMigrations( required string projectRoot ){
        var centralAbs = arguments.projectRoot & variables.CENTRAL_DIR;
        if ( !directoryExists( centralAbs ) ) {
            error( "Central migrations directory does not exist: " & centralAbs );
        }
        var discovered = discoverAddonMigrations( arguments.projectRoot );
        var staged   = [];
        var skipped  = [];
        var collisions = [];
        var seen     = {};   // targetName -> sourcePath; flag double-stages from different sources

        for ( var entry in discovered ) {
            var targetName = stagedTargetName( entry.addonId, entry.fileName );
            var targetPath = centralAbs & "/" & targetName;

            // Collision check across the discovery batch itself: two
            // add-ons shipping a file that maps to the same target.
            if ( structKeyExists( seen, targetName ) && seen[ targetName ] != entry.sourcePath ) {
                collisions.append( {
                    targetName : targetName,
                    sources    : [ seen[ targetName ], entry.sourcePath ]
                } );
                continue;
            }
            seen[ targetName ] = entry.sourcePath;

            // Idempotent: only copy when content changes.
            if ( fileExists( targetPath ) && hash( fileRead( entry.sourcePath ) ) == hash( fileRead( targetPath ) ) ) {
                skipped.append( { addonId : entry.addonId, source : entry.sourcePath, target : targetName, reason : "unchanged" } );
                continue;
            }

            fileCopy( entry.sourcePath, targetPath );
            staged.append( { addonId : entry.addonId, source : entry.sourcePath, target : targetName } );
        }

        var manifest = {
            stagedAt   : dateTimeFormat( now(), "yyyy-mm-dd HH:nn:ss" ),
            staged     : staged,
            skipped    : skipped,
            collisions : collisions
        };
        fileWrite( centralAbs & "/.staged.json", serializeJson( manifest ) );

        if ( collisions.len() ) {
            for ( var c in collisions ) {
                print.redLine( "Collision: two sources map to " & c.targetName ).toConsole();
                for ( var src in c.sources ) print.redLine( "  -> " & src ).toConsole();
            }
            error( "Refusing to stage: filename collision detected. Rename one of the sources." );
        }

        return manifest;
    }

    /**
     * Walk every source root and gather migration files. The "slug"
     * is the top-level folder name under the source root.
     *
     * Vendor modules (cbsecurity, qb, ...) ship their own migrations
     * but are not TesseraBX add-ons; we filter them out by requiring
     * that the module's ModuleConfig.bx declares a `tesserabx`
     * settings block. `sample-addons/` and `modules_app/` are
     * implicitly first-party and skip the manifest check.
     */
    private array function discoverAddonMigrations( required string projectRoot ){
        var out = [];
        for ( var rootName in variables.SOURCE_ROOTS ) {
            var rootAbs = arguments.projectRoot & rootName;
            if ( !directoryExists( rootAbs ) ) continue;
            var requiresManifest = ( rootName == "modules" );
            var children = directoryList( rootAbs, false, "query", "*", "name", "dir" );
            for ( var i = 1; i <= children.recordCount; i++ ) {
                var slug = children.name[ i ];
                var slugDir = rootAbs & "/" & slug;
                if ( requiresManifest && !isTesseraBXAddon( slugDir ) ) continue;
                for ( var sub in [ "migrations", "resources/migrations" ] ) {
                    var migDir = slugDir & "/" & sub;
                    if ( !directoryExists( migDir ) ) continue;
                    var files = directoryList( migDir, false, "query", "*.cfc", "name", "file" );
                    for ( var f = 1; f <= files.recordCount; f++ ) {
                        out.append( {
                            addonId    : slug,
                            sourceRoot : rootName,
                            fileName   : files.name[ f ],
                            sourcePath : migDir & "/" & files.name[ f ]
                        } );
                    }
                }
            }
        }
        return out;
    }

    /**
     * Heuristic: a TesseraBX add-on installed under modules/ ships a
     * ModuleConfig.bx that declares `settings.tesserabx`. A vendor
     * module (cbsecurity, qb, cbfs, ...) has its own ModuleConfig but
     * no such block. We grep the file for the string rather than
     * parsing BoxLang, which would require a runtime.
     */
    private boolean function isTesseraBXAddon( required string slugDir ){
        var configPath = arguments.slugDir & "/ModuleConfig.bx";
        if ( !fileExists( configPath ) ) return false;
        var content = fileRead( configPath );
        return findNoCase( "settings.tesserabx", content ) > 0
            || findNoCase( "tesserabx :", content ) > 0;
    }

    /**
     * Build the staged filename. We always prefix with `_addon_<slug>_`
     * because the prefix is what `.gitignore` keys on, AND because it
     * uniquely namespaces the component name in the global
     * cfmigrations table when two add-ons happen to pick the same
     * timestamp.
     *
     * If a source filename already begins with `_addon_`, we leave it
     * alone (idempotency under re-stage).
     */
    private string function stagedTargetName( required string slug, required string fileName ){
        if ( left( arguments.fileName, 7 ) == "_addon_" ) return arguments.fileName;
        return "_addon_" & arguments.slug & "_" & arguments.fileName;
    }

    private void function printStageReport( required struct report ){
        print.line( "" ).toConsole();
        print.cyanLine( "TesseraBX migration stager" ).toConsole();
        print.line( "  staged:     " & arguments.report.staged.len() ).toConsole();
        print.line( "  unchanged:  " & arguments.report.skipped.len() ).toConsole();
        print.line( "  collisions: " & arguments.report.collisions.len() ).toConsole();
        for ( var s in arguments.report.staged ) {
            print.greenLine( "  + " & s.target & "  (from " & s.source & ")" ).toConsole();
        }
    }

}
