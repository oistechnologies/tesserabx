/**
 * InstallAddons: CommandBox task that installs third-party TesseraBX
 * add-ons declared in a git-ignored box.addons.json manifest into
 * modules/, without ever writing to the tracked root box.json.
 *
 * Usage:
 *   box task run tasks/InstallAddons
 *   box run-script install:addons
 *
 * Why a separate manifest:
 *   The root box.json is tracked and is overwritten by `git pull` on
 *   every core update. Declaring add-on dependencies there would make
 *   updates clobber the operator's add-on list. box.addons.json is
 *   git-ignored, so it survives updates untouched. Each add-on is
 *   installed with save=false so the install never writes back to the
 *   tracked root box.json.
 *
 * Manifest shape (box.addons.json at the project root):
 *   {
 *       "addons": [
 *           "tesserabx-pm@^1.0.0",
 *           { "endpoint": "https://github.com/acme/tbx-slack.git#v2.0.0" }
 *       ]
 *   }
 *   Each entry is either a string endpoint (any CommandBox-resolvable
 *   id: a ForgeBox slug, a git URL, a local path) or a struct with an
 *   `endpoint` key. Add-ons land in modules/<slug>/ by default.
 *
 * No-op when box.addons.json is absent or its addons array is empty,
 * so a fresh clone with no add-ons builds cleanly.
 *
 * Why .cfc and not .bx:
 *   CommandBox 6.x hardcodes .cfc for task runners; the CommandBox
 *   runtime is Lucee, not BoxLang (see tasks/Migrate.cfc for the same
 *   note).
 */
component extends="commandbox.system.BaseTask" {

    variables.MANIFEST_FILE = "box.addons.json";

    function run(){
        // getCWD() is the project root (the host repo root, /app in the
        // container), so add-ons resolve against the project's box.json
        // and land in <project>/modules/<slug>/.
        var projectRoot = getCWD();
        if ( right( projectRoot, 1 ) != "/" ) projectRoot &= "/";
        var manifestPath = projectRoot & variables.MANIFEST_FILE;

        print.line( "" ).toConsole();
        print.cyanLine( "TesseraBX add-on installer" ).toConsole();

        if ( !fileExists( manifestPath ) ) {
            print.yellowLine( "  No " & variables.MANIFEST_FILE & " at " & manifestPath & ". Nothing to install." ).toConsole();
            return;
        }

        var manifest = "";
        try {
            manifest = deserializeJSON( fileRead( manifestPath ) );
        } catch ( any e ) {
            error( variables.MANIFEST_FILE & " is not valid JSON: " & e.message );
        }

        var entries = ( isStruct( manifest ) && structKeyExists( manifest, "addons" ) ) ? manifest.addons : [];
        if ( !isArray( entries ) || !entries.len() ) {
            print.yellowLine( "  " & variables.MANIFEST_FILE & " declares no add-ons. Nothing to install." ).toConsole();
            return;
        }

        var installed = [];
        var failed    = [];

        for ( var entry in entries ) {
            var endpoint = "";
            if ( isSimpleValue( entry ) ) {
                endpoint = trim( entry );
            } else if ( isStruct( entry ) && structKeyExists( entry, "endpoint" ) ) {
                endpoint = trim( entry.endpoint );
            }

            if ( !len( endpoint ) ) {
                print.yellowLine( "  Skipping an entry with no endpoint." ).toConsole();
                continue;
            }

            print.line( "  Installing add-on: " & endpoint ).toConsole();
            try {
                // save=false is essential: never write the add-on into
                // the tracked root box.json. Passing the endpoint as a
                // param value (not interpolated into the command string)
                // keeps a git ref suffix intact.
                command( "install" )
                    .params( id = endpoint, save = false )
                    .run();
                installed.append( endpoint );
            } catch ( any e ) {
                print.redLine( "    Failed: " & e.message ).toConsole();
                failed.append( endpoint );
            }
        }

        print.line( "" ).toConsole();
        print.greenLine( "  installed: " & installed.len() ).toConsole();
        if ( failed.len() ) {
            print.redLine( "  failed:    " & failed.len() ).toConsole();
            error( "One or more add-on installs failed. See the messages above." );
        }
    }

}
