## Extending Example Sync

This page is the developer-audience companion to **Using Example Sync**. It walks through every contribution this add-on makes so you can use it as a template for your own.

### File layout

```
sample-addons/example-sync/
  ModuleConfig.bx               <- manifest: every registration declared here
  config/Router.bx              <- module-local routes (most go through agent's router)
  handlers/
    Admin.bx                    <- /agent/admin/example-sync (admin connection page)
    Api.bx                      <- /api/v1/example-sync/* REST endpoints
  models/
    SyncService.bx              <- domain service (dashboard data + link logic)
    ExampleSyncChannelAdapter.bx        <- IChannelAdapter stub (Phase 5)
    ExampleSyncNotificationChannel.bx   <- INotificationChannel stub (Phase 10)
    ExampleSyncEmbeddingConsumer.bx     <- embedding consumer stub (Phase 7)
    LinkIssueExecutor.bx                <- automation action executor (Phase 6)
  views/
    admin/index.bxm             <- admin connection page view
    panels/linked_issue.bxm     <- ticket right-column panel (Phase 4)
    widgets/sync_status.bxm     <- dashboard widget (Phase 4)
  migrations/
    *_create_tickets_example_sync.cfc   <- entity extension table (Phase 9)
  resources/help/
    using.md                    <- this page's sibling (agent audience)
    extending.md                <- this page (developer audience)
  tests/specs/
    InstallSpec.bx              <- verifies every contribution registers
```

### Adapting it to your own add-on

1. Copy `sample-addons/example-sync/` to your own module location (`modules/<your-slug>/` for ForgeBox installs, or a separate repo).
2. Rename the slug. The slug appears in: `this.entryPoint`, `this.modelNamespace`, `this.cfmapping`, `addonId` in the manifest, every WireBox alias, every event key, table names, etc. The fastest way is a search-and-replace on the literal string `example-sync` / `exampleSync` / `example_sync` (table-name form).
3. Strip the contributions you don't need. Each entry in `settings.tesserabx` is independent; deleting `automationActions` deletes the action without affecting anything else.
4. Wire the contributions you keep through real implementations. Every stub method in this add-on returns canned data — replace those bodies with real domain logic.
5. Run `InstallSpec` in your tests folder to confirm registration. The spec exercises every registry the manifest touches.

### Conventions worth following

- **Stable ids everywhere.** A user's saved preferences, automation rules, and audit search filters all key off your `id`/`key` strings. Don't rename them across releases unless you also ship a migration that rewrites references.
- **One row, one purpose.** Entity-extension tables should have the FK as the primary key. Use the `EntityExtensionService` helper for read/write — it enforces tenancy.
- **No direct entity access across modules.** When you need data from a core entity (a ticket, a contact, an organization), go through that module's service layer, not through a direct query.
- **No em dashes in repo artifacts.** Use commas, parentheses, or restructured sentences instead.
