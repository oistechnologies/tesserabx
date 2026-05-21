/**
 * ScaffoldAddon: CommandBox task that lays down a skeleton TesseraBX
 * add-on under modules/<slug>/.
 *
 * Usage:
 *   box task run tasks/ScaffoldAddon <slug>
 *   box task run tasks/ScaffoldAddon <slug> <displayName>
 *   box task run tasks/ScaffoldAddon slug=<slug> displayName="Friendly Name"
 *
 * Why .cfc and not .bx:
 *   CommandBox 6.x hardcodes .cfc for task runners ("Task CFC doesn't
 *   exist." otherwise). The CommandBox runtime is Lucee, not BoxLang.
 *   The generated add-on itself uses .bx because it runs inside the
 *   TesseraBX BoxLang runtime, not inside the CommandBox runner.
 *
 * Why external templates:
 *   Inline string literals containing markdown # characters trip
 *   Lucee's pound-sign interpolation. Templates under tasks/templates/
 *   are loaded with fileRead() and tokens replaced with replaceNoCase.
 *
 * Produces:
 *   modules/<slug>/
 *     ModuleConfig.bx              -- pre-filled tesserabx manifest
 *     box.json                     -- minimal CommandBox box.json
 *     README.md                    -- next-steps notes for the author
 *     handlers/                    -- (empty placeholder)
 *     models/                      -- (empty placeholder)
 *     views/                       -- (empty placeholder)
 *     wires/                       -- (empty placeholder)
 *     migrations/                  -- (empty placeholder)
 *     resources/                   -- (empty placeholder)
 *     tests/specs/InstallSpec.bx   -- asserts manifest registers cleanly
 */
component extends="commandbox.system.BaseTask" {

    /**
     * @slug The add-on slug. Used as the folder name, the addonId,
     *       and the ColdBox module entry point. Use kebab-case.
     * @displayName Human-readable label. Defaults to title-cased slug.
     */
    function run( required string slug, string displayName = "" ){
        var slugClean = lcase( trim( arguments.slug ) );
        if ( !reFind( "^[a-z][a-z0-9\-]*$", slugClean ) ) {
            error( "Slug must start with a letter and contain only lowercase letters, digits, and hyphens. Got: " & arguments.slug );
        }

        var label = len( arguments.displayName )
            ? trim( arguments.displayName )
            : titleCaseSlug( slugClean );

        // resolvePath() anchors at the task file's directory (/app/tasks/)
        // not the project root. Use the user's CWD instead so the add-on
        // lands at <project>/modules/<slug> regardless of where the task
        // file lives.
        var projectRoot = getCWD();
        if ( right( projectRoot, 1 ) != "/" ) projectRoot &= "/";
        var root = projectRoot & "modules/" & slugClean;
        if ( directoryExists( root ) ) {
            error( "Target directory already exists: " & root );
        }

        print.line( "Scaffolding TesseraBX add-on [" & slugClean & "] at " & root ).toConsole();

        directoryCreate( root );
        var subFolders = [ "handlers", "models", "views", "wires", "migrations", "resources", "tests/specs" ];
        for ( var sub in subFolders ) {
            directoryCreate( root & "/" & sub, true );
            // Drop a hidden marker so empty folders survive git.
            fileWrite( root & "/" & sub & "/.gitkeep", "" );
        }

        var templatesRoot = projectRoot & "tasks/templates";
        renderTemplate( templatesRoot & "/ModuleConfig.bx.tpl", root & "/ModuleConfig.bx", slugClean, label );
        renderTemplate( templatesRoot & "/box.json.tpl",        root & "/box.json",        slugClean, label );
        renderTemplate( templatesRoot & "/README.md.tpl",       root & "/README.md",       slugClean, label );
        renderTemplate( templatesRoot & "/InstallSpec.bx.tpl",  root & "/tests/specs/InstallSpec.bx", slugClean, label );

        print.greenLine( "Done. Next steps:" ).toConsole();
        print.line( "  1. Edit modules/" & slugClean & "/ModuleConfig.bx to fill in the manifest details." ).toConsole();
        print.line( "  2. Reinit the app (touch index.bxm, hit /?fwreinit=1, or restart)." ).toConsole();
        print.line( "  3. Check the admin Add-ons page (lands in Phase 4) or the addons table." ).toConsole();
    }

    private string function titleCaseSlug( required string slug ){
        var parts = listToArray( arguments.slug, "-" );
        var out = [];
        for ( var p in parts ) {
            out.append( uCase( left( p, 1 ) ) & right( p, len( p ) - 1 ) );
        }
        return out.toList( " " );
    }

    private void function renderTemplate(
        required string templatePath,
        required string destPath,
        required string slug,
        required string label
    ){
        var content = fileRead( arguments.templatePath );
        content = replaceNoCase( content, "{{SLUG}}",  arguments.slug,  "all" );
        content = replaceNoCase( content, "{{LABEL}}", arguments.label, "all" );
        fileWrite( arguments.destPath, content );
    }

}
