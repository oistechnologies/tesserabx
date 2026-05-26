/**
 * GenerateDefaultLogos: one-off generator for the bundled default
 * logos under /includes/images/logos/.
 *
 * Usage (inside the dev container which has the JDK on classpath
 * for java.awt.* and javax.imageio):
 *
 *   docker compose -f compose.yaml -f compose.dev.yaml \
 *     exec app box task run tasks/GenerateDefaultLogos
 *
 * The generated PNGs are plain-but-on-brand placeholders the
 * email composer renders when an admin has not configured a
 * custom logo URL. Replace them with your own assets before
 * going to production; see /includes/images/logos/README.md.
 */
component {

    function run(){
        var logosDir = expandPath( "/includes/images/logos" );
        if ( !directoryExists( logosDir ) ) {
            directoryCreate( logosDir );
        }

        writeWideLogo( logosDir & "/tesserabx-logo-default.png", 240, 60 );
        writeSquareIcon( logosDir & "/tesserabx-icon-default.png", 256, 256 );

        print.greenLine( "Wrote logo files to " & logosDir );
    }

    /**
     * Wide email-header logo: transparent background, primary
     * brand color text "TesseraBX" centered. 240x60 is the
     * documented v1 size; it fits a 600px email column at 1x and
     * survives mobile rendering without cropping.
     */
    private void function writeWideLogo(
        required string path,
        required numeric width,
        required numeric height
    ){
        var BufferedImage = createObject( "java", "java.awt.image.BufferedImage" );
        var img = BufferedImage.init(
            javaCast( "int", arguments.width ),
            javaCast( "int", arguments.height ),
            BufferedImage.TYPE_INT_ARGB
        );
        var g = img.createGraphics();
        try {
            g.setRenderingHint(
                createObject( "java", "java.awt.RenderingHints" ).KEY_ANTIALIASING,
                createObject( "java", "java.awt.RenderingHints" ).VALUE_ANTIALIAS_ON
            );
            var Color = createObject( "java", "java.awt.Color" );
            g.setColor( Color.init(
                javaCast( "int", 13 ),
                javaCast( "int", 110 ),
                javaCast( "int", 253 )
            ) );
            var Font = createObject( "java", "java.awt.Font" );
            g.setFont( Font.init( "SansSerif", Font.BOLD, javaCast( "int", 28 ) ) );
            // Java 17 closed sun.font.FontDesignMetrics so we
            // cannot use stringWidth() / getAscent() directly.
            // Font.getStringBounds() via Rectangle2D is the public
            // path; the FontRenderContext from the Graphics2D is
            // what makes the measurement accurate.
            var label = "TesseraBX";
            var bounds = g.getFont().getStringBounds( label, g.getFontRenderContext() );
            var labelWidth = bounds.getWidth();
            var labelHeight = bounds.getHeight();
            var x = ( arguments.width - labelWidth ) / 2;
            // The bounds rectangle starts at the baseline; subtract
            // its minY (a negative number) to get the baseline
            // y-coordinate that drawString expects.
            var baseline = ( ( arguments.height - labelHeight ) / 2 ) - bounds.getY();
            g.drawString( label, javaCast( "int", x ), javaCast( "int", baseline ) );
        } finally {
            g.dispose();
        }
        var File = createObject( "java", "java.io.File" );
        var ImageIO = createObject( "java", "javax.imageio.ImageIO" );
        ImageIO.write( img, "PNG", File.init( arguments.path ) );
    }

    /**
     * Square icon: solid primary color background with a single
     * "T" letterform centered. Used as the favicon / avatar
     * fallback and as a square logo for cards.
     */
    private void function writeSquareIcon(
        required string path,
        required numeric width,
        required numeric height
    ){
        var BufferedImage = createObject( "java", "java.awt.image.BufferedImage" );
        var img = BufferedImage.init(
            javaCast( "int", arguments.width ),
            javaCast( "int", arguments.height ),
            BufferedImage.TYPE_INT_ARGB
        );
        var g = img.createGraphics();
        try {
            var Color = createObject( "java", "java.awt.Color" );
            g.setRenderingHint(
                createObject( "java", "java.awt.RenderingHints" ).KEY_ANTIALIASING,
                createObject( "java", "java.awt.RenderingHints" ).VALUE_ANTIALIAS_ON
            );
            g.setColor( Color.init(
                javaCast( "int", 13 ),
                javaCast( "int", 110 ),
                javaCast( "int", 253 )
            ) );
            g.fillRoundRect(
                javaCast( "int", 0 ),
                javaCast( "int", 0 ),
                javaCast( "int", arguments.width ),
                javaCast( "int", arguments.height ),
                javaCast( "int", 48 ),
                javaCast( "int", 48 )
            );
            g.setColor( Color.WHITE );
            var Font = createObject( "java", "java.awt.Font" );
            g.setFont( Font.init( "SansSerif", Font.BOLD, javaCast( "int", 180 ) ) );
            var label = "T";
            var bounds = g.getFont().getStringBounds( label, g.getFontRenderContext() );
            var x = ( arguments.width - bounds.getWidth() ) / 2;
            var baseline = ( ( arguments.height - bounds.getHeight() ) / 2 ) - bounds.getY();
            g.drawString( label, javaCast( "int", x ), javaCast( "int", baseline ) );
        } finally {
            g.dispose();
        }
        var File = createObject( "java", "java.io.File" );
        var ImageIO = createObject( "java", "javax.imageio.ImageIO" );
        ImageIO.write( img, "PNG", File.init( arguments.path ) );
    }

}
