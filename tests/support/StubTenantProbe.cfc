/**
 * Test fixture: a TenantContextProbe stand-in that always returns
 * the value it was constructed with. Used by TenantScopeSpec to
 * simulate "logged-in Contact" vs "logged-in Agent" without standing
 * up cbauth's full session machinery.
 */
component {

    public any function init( any tenantId ){
        variables._tenantId = arguments.tenantId ?: javaCast( "null", "" );
        return this;
    }

    public any function currentTenantId(){
        if ( isNull( variables._tenantId ) ) {
            return javaCast( "null", "" );
        }
        return variables._tenantId;
    }

}
