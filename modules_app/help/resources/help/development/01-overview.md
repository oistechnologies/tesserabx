## What an add-on is

An add-on is a **standard ColdBox 8+ module** that lives in one of TesseraBX's standard module locations:

- `modules_app/` for first-party add-ons that ship with TesseraBX itself
- `modules/` for third-party add-ons installed through CommandBox (`box install <slug>`)

ColdBox discovers both locations automatically. No custom loader, no special path. If your module loads in a stock ColdBox app, it loads in TesseraBX too.

What makes a ColdBox module a TesseraBX add-on is one extra block of settings inside its `ModuleConfig.bx`:

```boxlang
class {

    function configure(){
        settings = {
            tesserabx : {
                addonId         : "example-jira",
                displayName     : "Jira Sync",
                version         : "1.0.0",
                minCoreVersion  : "0.0.1",
                maxCoreVersion  : "",
                contributesTo   : [ "navigation", "ticketPanel", "automationAction" ],
                requiresAi      : false
            }
        };
        // ...rest of the module's normal configure() body
    }
}
```

A module without a `settings.tesserabx` block is a normal ColdBox module. TesseraBX does not surface it in the admin UI and does not track its enablement.

---

