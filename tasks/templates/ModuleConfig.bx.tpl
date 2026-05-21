/**
 * {{LABEL}} (TesseraBX add-on).
 *
 * Standard ColdBox module that contributes to TesseraBX through the
 * settings.tesserabx manifest block. See docs/EXTENSIONS.md in the
 * core TesseraBX repo for the contract.
 */
class {

    this.title              = "{{LABEL}}";
    this.author             = "";
    this.webURL             = "";
    this.description        = "TesseraBX add-on: {{LABEL}}";
    this.version            = "0.1.0";
    this.viewParentLookup   = true;
    this.layoutParentLookup = true;
    this.entryPoint         = "{{SLUG}}";
    this.modelNamespace     = "{{SLUG}}";
    this.cfmapping          = "modules.{{SLUG}}";
    this.autoMapModels      = false;
    this.dependencies       = [];

    function configure(){
        // Explicit `variables.` prefix is REQUIRED: BoxLang assigns
        // unscoped names inside a function to function-local scope,
        // so `settings = {...}` would be invisible to ColdBox (which
        // reads settings from the class variables scope). The same
        // applies to routes / interceptorSettings / interceptors.
        variables.settings = {
            tesserabx : {
                addonId         : "{{SLUG}}",
                displayName     : "{{LABEL}}",
                version         : "0.1.0",
                minCoreVersion  : "0.0.1",
                // Leave maxCoreVersion blank for an open upper bound
                // (accepted on any core version >= minCoreVersion).
                maxCoreVersion  : "",
                contributesTo   : [],
                requiresAi      : false
            }
        };

        variables.routes = [];

        variables.interceptorSettings = { customInterceptionPoints : [] };
        variables.interceptors        = [];
    }

    function onLoad(){}
    function onUnload(){}

}
