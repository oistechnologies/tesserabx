/**
 * InstallSpec: smoke-test that the add-on registers cleanly.
 *
 * Asserts the manifest block is well-formed and that the
 * AddonRegistryService records this add-on as compatible at the
 * current core version.
 */
class extends="coldbox.system.testing.BaseTestCase" appMapping="/" {

    function beforeAll(){
        super.beforeAll();
        super.setup();
        variables.svc = getController().getWireBox().getInstance( "AddonRegistryService@core" );
    }

    function run(){
        describe( "{{LABEL}} add-on installation", function(){

            it( "registers in the addons table after discovery", function(){
                var row = variables.svc.findById( "{{SLUG}}" );
                expect( row ).notToBeNull();
                expect( row.addonId ).toBe( "{{SLUG}}" );
                expect( row.compatible ).toBeTrue();
            } );

            it( "is enabled globally by default", function(){
                expect( variables.svc.isEnabled( "{{SLUG}}" ) ).toBeTrue();
            } );

        } );
    }

}
