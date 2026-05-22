## Help pages and sections

The `help` module is itself an extension point. Every core module and every add-on contributes pages and sections to the in-app help system through the standard manifest pattern.

### Declaring a section

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.helpSections = [
    {
        id         : "billing",
        title      : "Billing",
        audience   : "agent",
        sortWeight : 500,
        icon       : "bi bi-receipt"
    }
];
```

| Field        | Required    | Notes                                                                       |
| ------------ | ----------- | --------------------------------------------------------------------------- |
| `id`         | yes         | Stable identifier, conventionally one word.                                 |
| `title`      | yes         | Human label for the section landing.                                        |
| `audience`   | yes         | `public`, `client`, `agent`, or `developer`.                                |
| `sortWeight` | recommended | Lower sorts first. Default 500.                                             |
| `icon`       | recommended | Bootstrap-icon class (e.g. `bi bi-receipt`).                                |

### Declaring a page

```
settings.tesserabx.helpPages = [
    {
        id         : "billing.creating-an-invoice",
        section    : "billing",
        title      : "Creating an invoice",
        audience   : "agent",
        sortWeight : 10,
        source     : "resources/help/billing/creating-an-invoice.md",
        searchable : true,
        keywords   : [ "invoice", "billing", "charge" ]
    }
];
```

| Field        | Required    | Notes                                                                                |
| ------------ | ----------- | ------------------------------------------------------------------------------------ |
| `id`         | yes         | Stable identifier, conventionally `<section>.<slug>`.                                |
| `section`    | yes         | Must match a registered section id.                                                  |
| `title`      | yes         | Page title.                                                                          |
| `audience`   | yes         | `public`, `client`, `agent`, or `developer`. Cannot be broader than the section.     |
| `sortWeight` | recommended | Lower sorts first within the section. Default 500.                                   |
| `source`     | yes         | Module-relative path to the markdown file.                                           |
| `searchable` | recommended | Default true. Set false to exclude from search results.                              |
| `keywords`   | optional    | Extra search terms beyond the title and body content.                                |

### Audience model

The four audiences form a hierarchy. Any signed-in agent can see public and client pages too; any user with `help.developer` permission can see everything.

| Audience    | Who sees it                                       |
| ----------- | ------------------------------------------------- |
| `public`    | Anyone (anonymous portal visitors included).      |
| `client`    | Signed-in contacts on the portal, and all agents. |
| `agent`     | Signed-in agents on the provider dashboard.       |
| `developer` | Agents with the `help.developer` permission.      |

The `help.developer` permission is auto-granted to the `agent-admin` role. Grant it explicitly to other roles via the admin Users page.

### Search behavior

Search is wired through Phase 7's `EmbeddingConsumerRegistry`. When `AI_ENABLED=true`, the search box runs a vector similarity search; when off, the same box falls back to substring + keyword matching. The UI never advertises which mode is active. Audience filtering runs AFTER ranking either way, so a page above the viewer's audience is never visible in results.

### Public extension contract

```
var pageReg     = wirebox.getInstance( "HelpPageRegistry@help" );
var sectionReg  = wirebox.getInstance( "HelpSectionRegistry@help" );
var resolver    = wirebox.getInstance( "HelpAudienceResolver@help" );

var allSections = sectionReg.listAll();
var pagesInDev  = pageReg.listForSection( "development" );
var canSee      = resolver.canSeePage( viewer, page );
```
