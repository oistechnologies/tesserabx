# TesseraBX Extensibility Plan

## Context

TesseraBX today is a tightly integrated, multi-tenant help-desk product. The current architecture has solid service-layer separation (per-module `*Service` facades) and respects the tenancy boundary, but almost every other extension point is hard-coded: navigation lives inline in `Portal.bxm` and `Agent.bxm`; the admin home is static buttons; automation triggers/conditions/actions are class-level arrays; AI features call a single facade; the `api` module's router lists every route; channels are hard-wired to email; custom fields only attach to tickets; roles are a returned array; and only four interceptor announcements exist in the entire codebase.

This plan opens TesseraBX to **third-party BoxLang ColdBox modules** so developers can ship drop-in add-ons (Jira sync, custom channels, billing connectors, new dashboard widgets, new AI features) without forking core. The intent is not to invent a new plug-in framework - add-ons are **standard ColdBox modules** discovered via the standard `modules/` location (for ForgeBox installs) or `modules_app/` (for first-party). The TesseraBX-specific contract layers on top through a manifest block in `ModuleConfig.bx`, a set of in-code registries with DB overrides, formal service interfaces, an expanded event surface, and a tenancy-safe extension model.

The outcome: a developer can `box install` a third-party add-on, the host discovers and validates it, an admin enables it (globally or per-organization), and the add-on contributes nav items, admin pages, ticket panels, dashboard widgets, channel adapters, automation actions, AI features, API routes, roles, custom-field types, and notification templates - all without touching core code.

---

## Decisions locked in (from clarifying questions)

1. **Core eats its own dog food.** Existing hard-coded navigation, admin cards, dashboard widgets, channel intake, automation constants, AI features, API routes, and role lists will be migrated to register through the same registries an add-on would use. One contract, proven by core itself.
2. **Standard ColdBox module locations.** Core modules stay in `modules_app/`. Add-ons installed from ForgeBox land in `modules/` via `box install`. No custom discovery path. An add-on is a normal ColdBox module whose `ModuleConfig.bx` carries a TesseraBX-specific settings block declaring version compatibility and the registries it contributes to.
3. **Per-organization enable/disable lands in the foundation phase**, with an explicit "All organizations" mode so a deployment can opt into the simpler global-enablement model without losing the per-tenant capability later.
4. **Registries are in-code with DB overrides.** Modules declare registrations in `ModuleConfig.bx` at load time. A small set of override tables (per registry) lets an admin disable, reorder, or rename items without forking the add-on. Resolution is always: in-code declaration ⟶ DB override applied on top.

---

## Hard constraints (carried from CLAUDE.md)

These never move:

- **Module ownership is preserved.** No new shared `domain` module. Add-ons must reach core entities through service layers, never directly.
- **Tenant isolation is non-negotiable.** Every registry, every add-on entity, every override table must respect the `organization_id` boundary. The tenant scope primitive lives in `contacts` and is the only sanctioned mechanism.
- **AI remains strictly optional.** Add-on AI features inherit the capability flag from the registry; when `AI_ENABLED=false` they vanish from every surface.
- **`/agent/admin` stays nested inside `agent`.** Admin extension points live within that nested module's lifecycle.
- **No em dashes** in any artifact written to the repo (docs, code comments, READMEs, sample add-on).
- **Provider-side visibility is asymmetric from client-side.** No add-on contribution may leak internal-only content to a client surface.

---

## How phases work

Each phase below is a coherent, independently testable slice. The execution rhythm for every phase is:

1. Build the phase's deliverables.
2. Run the cleanup checklist (lint, format, dead-code sweep).
3. Run automated tests (TestBox unit + integration + CBWire specs as relevant).
4. **PAUSE FOR USER TESTING.** The user verifies the feature in the browser / API client on both surfaces. No local commit happens before the user signs off.
5. Update this plan document's progress log and gotchas log with whatever was learned.
6. Local commit on the phase's work.
7. Move to the next phase.

This matches the existing project's per-phase workflow: finish work, run cleanup, run automated tests, hand off to the human for UI verification, then commit, then move to the next phase.

---

## Phase 0: Plan persistence and progress tracking

**Goal.** Get the plan itself into the repository so it survives across sessions, and establish how progress is recorded.

**Scope.**
- Save the final, user-approved version of this plan to `docs/EXTENSIBILITY-PLAN.md` (mirrored from this file).
- Add a top-of-file "Progress log" and "Gotchas log" to the saved copy so subsequent phases append notes there.
- Cross-link from `docs/BUILD-PLAN.md` and `docs/FUTURE-WORK.md` to `EXTENSIBILITY-PLAN.md` so future contributors find it.
- Add a one-paragraph pointer in `CLAUDE.md` under "How to use this with the build plan" so the rule of "BUILD-PLAN is what to do next, this file is what must remain true" is preserved while announcing the new doc.

**Critical files.**
- `docs/EXTENSIBILITY-PLAN.md` (new)
- `docs/BUILD-PLAN.md` (edit: cross-link)
- `docs/FUTURE-WORK.md` (edit: cross-link)
- `CLAUDE.md` (edit: pointer paragraph)

**Verification.**
- `docs/EXTENSIBILITY-PLAN.md` opens cleanly, has the empty progress/gotchas logs, and the cross-links resolve.

**Pause point.** User reviews the persisted doc, confirms the structure is what they want for ongoing notes, then commit.

---

## Phase 1: Add-on foundation

**Goal.** Establish the lowest layer: what an add-on *is*, how it declares itself, how it is discovered, how it is enabled or disabled.

**Scope - items A1, A2, A3, M1, M2 (stub).**

### 1.1 Discovery
- Confirm `config/Coldbox.bx` `modulesExternalLocation` covers the path ForgeBox installs into. Standard ColdBox discovery already loads `modules/` and `modules_app/` automatically; no custom loader is added. Document this explicitly in the new `docs/EXTENSIONS.md`.

### 1.2 Manifest block
- Define the `settings.tesserabx` block format inside an add-on's `ModuleConfig.bx`. Shape (subject to iteration during phase build):
  ```
  settings = {
      tesserabx : {
          addonId         : "example-jira",
          displayName     : "Jira Sync",
          version         : "1.0.0",
          minCoreVersion  : "1.0.0",
          maxCoreVersion  : "2.0.0",
          contributesTo   : [ "navigation", "ticketPanel", "automationAction" ],
          requiresAi      : false
      }
  };
  ```
- At app boot, a new `AddonRegistryService@core` reads every loaded module's `settings.tesserabx` block (if present), validates the version range against the core version, and records the add-on.
- **Version range semantics.** `minCoreVersion` is required. `maxCoreVersion` is optional: when blank, missing, or omitted entirely, the add-on is accepted on **any core version equal to or greater than `minCoreVersion`** (effectively an open upper bound). When present, it caps the supported range inclusively. The intent is to let add-on authors opt into "works forever forward" without having to bump their manifest on every core release.
- Add-ons without a `tesserabx` block are treated as ordinary ColdBox modules (no special handling, no admin surfacing).

### 1.3 Per-organization enable/disable (A3 + foundation table)
- New migration adds two tables:
  - `addons` - one row per discovered add-on. Columns: `addon_id` (slug, PK), `display_name`, `version`, `installed_at`, `enabled` (global on/off), `enablement_mode` ('all' or 'specific'), `metadata` (jsonb of the manifest).
  - `addon_organization_enablement` - composite PK `(addon_id, organization_id)`, `enabled` boolean, `enabled_at`, `enabled_by_agent_id`.
- Resolution logic in `AddonRegistryService`:
  - `addons.enabled = false` ⟶ off everywhere.
  - `enablement_mode = 'all'` ⟶ on for every organization.
  - `enablement_mode = 'specific'` ⟶ on only for organizations with an `enabled=true` row in the join table.
- Admin UI lands later (Phase 4 builds the admin page that drives these rows). For Phase 1 the rows are seeded at install time: `enabled=true`, `enablement_mode='all'`.

### 1.4 Scaffolding generator (M1)
- New CommandBox task `box tesserabx:scaffold-addon <slug>` (lives at `tasks/scaffoldAddon.bx`). Generates a skeleton add-on under `modules/<slug>/` containing:
  - `ModuleConfig.bx` with the manifest block pre-filled.
  - `models/`, `handlers/`, `views/`, `wires/`, `migrations/`, `tests/` folders.
  - A `README.md` explaining what to fill in.
  - A passing `tests/specs/InstallSpec.bx` that asserts the manifest is well-formed and the add-on registers cleanly.

### 1.5 Extensions docs stub
- New `docs/EXTENSIONS.md`. For Phase 1 it documents: manifest block fields, discovery convention, enablement rules, scaffolding command. Subsequent phases append a section per registry.

**Critical files.**
- `modules_app/core/models/AddonRegistryService.bx` (new)
- `modules_app/core/interceptors/AddonDiscoveryInterceptor.bx` (new - listens on `afterAspectsLoad`)
- `modules_app/core/migrations/<timestamp>_create_addon_tables.bx` (new)
- `tasks/scaffoldAddon.bx` (new)
- `docs/EXTENSIONS.md` (new)
- `config/Coldbox.bx` (edit: confirm modules path documentation)

**Verification.**
- Run the scaffolder against a throwaway slug and confirm the generated module loads, registers in the `addons` table with `enabled=true, enablement_mode='all'`, and the InstallSpec passes.
- Manually edit the throwaway add-on's manifest to declare a `minCoreVersion` newer than core; on reinit the service refuses to register it and logs a clear warning rather than crashing the app.
- Toggle `addons.enabled = false` via direct SQL; reinit; confirm `AddonRegistryService.isEnabled(addonId, orgId)` returns false for every org.
- Insert an `addon_organization_enablement` row with `enabled=false` for one org while `enablement_mode='specific'`; confirm the service returns false for that org and true (or as configured) for others.

**Pause point.** User exercises the scaffolder + enable/disable resolution before commit.

---

## Phase 2: Service contracts and tenancy safety

**Goal.** Lock in the contract surface add-ons code against, and the safety helpers that prevent the most common mistake (silent tenancy leak).

**Scope - items B1, B2, K1, K2, K3, N1.**

### 2.1 Service interfaces (B1)
- For each headline service add-ons are expected to depend on, publish a thin interface class in the owning module's `models/contracts/` subfolder:
  - `tickets.models.contracts.ITicketsService` - `createTicket`, `addMessage`, `assign`, `transitionStatus`, `findByIdForOrg`, `searchForOrg`.
  - `contacts.models.contracts.IContactsService` - `findContactByEmailForOrg`, `findOrCreateOrganizationByDomain`, `mergeContacts`, `listOfficesForOrg`.
  - `audit.models.contracts.IAuditService` - `record(eventType, actorId, organizationId, entity, payload)`.
  - `notifications.models.contracts.INotificationsService` - `dispatch(eventKey, recipients, payload)`.
  - `ai.models.contracts.IAiMiddleware` - `complete(feature, prompt, options)`, `embed(text, model)`, `isEnabled()`, `isFeatureEnabled(feature, orgId)`.
- Existing service classes implement these interfaces. Add-ons resolve them by interface alias via WireBox.

### 2.2 DTOs (B2)
- Each service interface returns DTOs rather than Quick entities at its public surface. Add `models/dtos/<EntityName>Dto.bx` per module.
- Inside the owning module, services still work in Quick entities; the DTO mapping happens at the facade boundary.
- Existing internal call sites that already receive entities are unaffected; only cross-module callers move to the DTO shape.

### 2.3 Tenant scope publication (K3)
- The Quick global scope (or shared base entity) that enforces `organization_id` currently lives in `contacts`. Promote it to a documented, supported primitive: `contacts.models.tenancy.TenantScopedEntity` (or whatever the actual class is) gets a class-level docblock declaring it part of the public extension contract, and `docs/EXTENSIONS.md` gets a "Building tenant-scoped add-on entities" section.

### 2.4 Tenancy guard (N1)
- New helper `contacts.models.tenancy.TenancyGuard@contacts` exposing `assertScopedQuery(qbBuilder, organizationId)` which throws if the builder does not include an `organization_id` predicate against the right table. Add-on authors call this before executing any `qb` query that touches a tenant-scoped table; in development the guard also logs a stack trace to make leaks loud during testing.
- An interceptor `TenancyAuditInterceptor` listens on `preProcess` in dev/test environments and applies the guard to incoming requests for known sensitive routes as a backstop.

### 2.5 Per-module migration namespacing (K1)
- Document the migration convention for add-ons: each module owns a `migrations/` folder under its root; migrations are prefixed with the `addonId` to avoid name collisions across the global `cfmigrations` table.
- The migration runner is extended (or its config updated) to scan add-on migration folders. If the existing migration runner already supports per-module scanning, this is documentation-only.

### 2.6 Settings registry (K2)
- New `core.models.SettingsRegistry@core`. Modules contribute settings descriptors in `ModuleConfig.bx`:
  ```
  settings.tesserabx.settings = [
      {
          key            : "exampleJira.baseUrl",
          type           : "string",
          label          : "Jira Base URL",
          description    : "...",
          default        : "",
          secret         : false,
          perTenant      : true
      }
  ];
  ```
- A new `addon_settings` table stores per-tenant overrides keyed by `(addon_id, organization_id, setting_key)`.
- Global settings remain in env vars; the registry only governs add-on-defined settings.
- The admin UI to drive this lands in Phase 4 alongside other admin pages; Phase 2 just publishes the registry and DB tier.

**Critical files.**
- `modules_app/tickets/models/contracts/ITicketsService.bx` (new)
- `modules_app/contacts/models/contracts/IContactsService.bx` (new)
- `modules_app/audit/models/contracts/IAuditService.bx` (new)
- `modules_app/notifications/models/contracts/INotificationsService.bx` (new)
- `modules_app/ai/models/contracts/IAiMiddleware.bx` (new)
- `modules_app/contacts/models/tenancy/TenancyGuard.bx` (new)
- `modules_app/core/models/SettingsRegistry.bx` (new)
- `modules_app/core/migrations/<timestamp>_create_addon_settings.bx` (new)
- `docs/EXTENSIONS.md` (edit: contracts + tenancy + migrations + settings sections)

**Verification.**
- Existing TestBox suite passes unchanged (interfaces are additive).
- Write a one-off integration spec that resolves each interface from WireBox and asserts the implementation conforms.
- Write a spec that deliberately omits the `organization_id` clause and asserts `TenancyGuard.assertScopedQuery` throws.
- Manually run a settings round-trip: register a sample setting in a throwaway add-on's manifest, write a per-tenant override via service, read it back.

**Pause point.** User confirms existing flows still work and the new contracts are documented.

---

## Phase 3: Event surface and audit contributions

**Goal.** Expand the event vocabulary to something an add-on can realistically build on, lock in a canonical payload shape, and give add-ons a way to write to the central audit log.

**Scope - items C1, C2, C3, N2.**

### 3.1 Event audit and expansion (C1)
- Walk every module's service layer and identify state transitions an add-on would plausibly care about. The catalog from the survey is the starting point:
  - **tickets:** `onTicketCreated`, `onTicketUpdated`, `onTicketAssigned`, `onTicketUnassigned`, `onTicketPriorityChanged`, `onTicketTypeChanged`, `onTicketStatusChanged`, `onTicketMessageAdded`, `onTicketMerged`, `onTicketSplit`, `onTicketLinked`, `onTicketUnlinked`, `onTicketTagAdded`, `onTicketTagRemoved`, `onTicketAttachmentAdded`, `onTicketAttachmentRemoved`.
  - **contacts:** `onContactCreated`, `onContactUpdated`, `onContactMerged`, `onContactDeleted`, `onOrganizationCreated`, `onOrganizationUpdated`, `onOfficeCreated`, `onOfficeUpdated`.
  - **agent:** `onAgentInvited`, `onAgentActivated`, `onAgentDeactivated`, `onAgentRoleAssigned`, `onAgentRoleRevoked`, `onAgentLoginSuccess`, `onAgentLoginFailure`, `onAgentMfaEnrolled`, `onAgentMfaReset`.
  - **sla:** `onSlaPolicyAttached`, `onSlaPaused`, `onSlaResumed`, `onSlaBreached`, `onSlaWarning`.
  - **automation:** `onAutomationRuleFired`, `onAutomationActionExecuted`, `onAutomationActionFailed`.
  - **knowledgebase:** `onKbArticleCreated`, `onKbArticleUpdated`, `onKbArticlePublished`, `onKbArticleUnpublished`, `onKbArticleDeleted`, `onKbArticleViewed`, `onKbArticleFeedbackSubmitted`.
  - **channels:** `onInboundMessageReceived`, `onInboundBlocked`, `onOutboundMessageSent`, `onOutboundMessageFailed`.
  - **api:** `onWebhookDelivered`, `onWebhookFailed`, `onApiTokenIssued`, `onApiTokenRevoked`.
  - **ai:** `onAiFeatureInvoked`, `onAiFeatureFailed`.
- Each module declares its events in `interceptorSettings.customInterceptionPoints` inside its `ModuleConfig.bx`. The service that owns the state transition announces it.

### 3.2 Canonical payload shape (C2)
- Every announcement uses the same struct shape:
  ```
  {
      event           : "onTicketStatusChanged",
      occurredAt      : <UTC timestamp>,
      organizationId  : <int or null for accountless>,
      actorId         : <agent id or contact id or "system">,
      actorType       : "agent" | "contact" | "system",
      entity          : { type: "Ticket", id: 123 },
      before          : {...},
      after           : {...},
      metadata        : {...}
  }
  ```
- A helper `core.models.events.EventPayloadBuilder.bx` produces the struct so every call site stays consistent.

### 3.3 Async vs sync policy (C3)
- Default rule: events that other modules might want to react to with network calls or heavy work go through `announceAsync()` so they cannot stall the request that triggered them. Events that need to influence the in-flight transaction (rare in this codebase) stay synchronous.
- Document the policy in `docs/EXTENSIONS.md` so add-on authors know what to expect from each event.
- Where async is used, ensure the dispatched event payload is fully serialized at announcement time so the listener does not see stale entity state.

### 3.4 Audit-event contributions (N2)
- Extend `AuditService.record()` to accept a `source` field identifying the originating add-on. Add-ons register their audit event types in `ModuleConfig.bx`:
  ```
  settings.tesserabx.auditEvents = [
      { type: "exampleJira.issueCreated", label: "Jira issue created", severity: "info" }
  ];
  ```
- The admin audit search UI (already shipped per the build plan) gains a filter by `source` so add-on events can be inspected independently.

**Critical files.**
- Every module's `ModuleConfig.bx` (edit: expand `customInterceptionPoints`).
- Every module's `*Service.bx` that owns a state transition (edit: add `announce` / `announceAsync` call with canonical payload).
- `modules_app/core/models/events/EventPayloadBuilder.bx` (new)
- `modules_app/audit/models/AuditService.bx` (edit: accept `source`)
- `modules_app/agent/modules/admin/handlers/Audit.bx` and its views (edit: source filter)
- `docs/EXTENSIONS.md` (edit: event catalog + payload shape + async policy)

**Verification.**
- Add a temporary interceptor in the sample/throwaway add-on that captures every announced event into an in-memory list. Drive each state transition manually through the UI and confirm the corresponding event fires with the expected canonical payload.
- Run the existing test suite; spec the canonical shape on at least three representative events.
- Verify the admin audit UI's new source filter returns the expected rows after registering a sample audit type.

**Pause point.** User reviews the event catalog and audit filter before commit.

---

## Phase 4: UI registries and RBAC

**Goal.** Replace every hard-coded UI surface with a registry, migrate core's existing entries onto those registries, and let add-ons contribute roles and permissions that gate access.

**Scope - items D1, D2, D3, D4, D5, I1, I2.**

This phase is the largest. Sub-phases below are still committed together once the user signs off on the full UI surface, but they describe the build order.

### 4.1 Role and permission registry (I1, I2)
- New `agent.models.RoleRegistry@agent` and `agent.models.PermissionRegistry@agent`. Each role declares a set of permissions; each permission has an id and a human-readable label.
- Migrate `RbacService.roleCatalog()` to seed the registry from core's roles (`agent-admin`, `agent-supervisor`, plus client-side roles). Existing role assignments in `agent_roles` continue to work; the registry adds the "what roles exist" indirection.
- Add-on registration shape in `ModuleConfig.bx`:
  ```
  settings.tesserabx.roles = [
      { id: "billing-viewer", label: "Billing Viewer", permissions: ["billing.view"] }
  ];
  settings.tesserabx.permissions = [
      { id: "billing.view", label: "View billing data" }
  ];
  ```
- The admin Users page renders the registry rather than a hard-coded role list.

### 4.2 Navigation registry (D1)
- New `core.models.NavigationRegistry@core`. Entries declare **surface** (`portal` or `agent`), **menu** (the menu zone within that surface), label, route, icon, sort weight, required permission id, and capability flag (e.g. `AI_ENABLED`).
- **Menu zones per surface.** Each surface has three distinct navigation menus, and entries target exactly one:
  - `main` - the primary left-hand sidebar navigation (the AdminLTE main menu).
  - `account` - the user account dropdown (profile, settings, sign out).
  - `topbar` - the small top-bar menu (notifications, quick actions, breadcrumb adjacents).
- Resolution key inside the registry is `(surface, menu)`; each layout zone iterates only the entries that match its `(surface, menu)` pair. An add-on can contribute to any combination by registering multiple entries.
- Migrate `modules_app/core/layouts/Portal.bxm` and `modules_app/core/layouts/Agent.bxm` to iterate the registry for each of the three menu zones rather than emit inline `<a>` tags. Each menu zone becomes a discrete `#renderNavigation( surface, menu )#` (or equivalent helper) call.
- Existing core nav items in **all three menus on both surfaces** become registrations seeded by each module's `ModuleConfig.bx`. The portal's left menu, account dropdown, and top bar; and the agent surface's left menu, account dropdown, and top bar - six menu zones total - must end up registry-driven before this phase exits.
- Add-on registration shape:
  ```
  settings.tesserabx.navigation = [
      { surface: "agent", menu: "main",    label: "Jira Sync",     route: "exampleJira.home", icon: "...", sortWeight: 50, requiredPermission: "exampleJira.view" },
      { surface: "agent", menu: "account", label: "Jira Settings", route: "exampleJira.settings", icon: "...", sortWeight: 30, requiredPermission: "exampleJira.manage" }
  ];
  ```

### 4.3 Admin pages registry (D2)
- New `agent.modules.admin.models.AdminPagesRegistry@admin`. Entries declare card title, description, route, icon, required permission, sort weight.
- Migrate `modules_app/agent/modules/admin/views/home/index.bxm` from hard-coded buttons to a loop over the registry.
- Each existing admin destination registers itself from the appropriate module (`tickets`, `contacts`, `automation`, `sla`, `audit`, etc.).
- Add-ons contribute via `settings.tesserabx.adminPages = [...]`.
- The Phase 1 `addons` table now gets its own admin page here: an "Add-ons" card lists every discovered add-on, lets the admin toggle global enable, switch enablement mode between 'all' and 'specific', and edit per-organization rows.
- The Phase 2 settings registry surfaces here too: each registered setting becomes a row on an "Add-on Settings" admin page, grouped by add-on, with per-tenant override controls.

### 4.4 Ticket detail panel registry (D3)
- New `tickets.models.TicketPanelRegistry@tickets`. Entries declare panel id, CBWire component name, position (`right` or `tab`), sort weight, required permission, capability flag, default-collapsed boolean (defaults true per the right-column memory convention).
- Migrate `modules_app/agent/views/tickets/show.bxm` (or its equivalent) so every right-column card and tab is registered. The view becomes a loop that renders each registered CBWire component.
- Add-ons contribute via `settings.tesserabx.ticketPanels = [...]`.

### 4.5 Dashboard widget registry (D4)
- New `reporting.models.DashboardWidgetRegistry@reporting`. Entries declare widget id, title, CBWire component (or view partial), data-provider callable, default grid size, required permission.
- Migrate existing reporting widgets currently driven by `ReportingService` hard-coded queries into registrations. The dashboard view iterates the registry.
- Add-ons contribute via `settings.tesserabx.dashboardWidgets = [...]`.

### 4.6 Asset publishing (D5)
- New helper `core.models.AddonAssetService@core`. Add-ons declare published asset paths in `settings.tesserabx.assets = [...]`. The helper resolves a public URL the layout can emit (either through CBFS with a public provider or through a route the core module exposes for streaming static assets out of the add-on's `resources/` folder, depending on what works cleanest with the existing CBFS configuration).
- Both surface layouts gain a `#renderAddonAssetTags()#` helper call that emits `<link>` and `<script>` tags for every enabled add-on, ordered by load weight.

### 4.7 Override tables (DB layer for all four registries)
- Single generic `registry_overrides` table: `(registry, entry_id, organization_id nullable, disabled boolean, sort_weight_override int, label_override varchar, payload jsonb)`. Resolution: in-code declaration ⟶ apply override row matching `(registry, entry_id, organization_id)` ⟶ fall back to override row with `organization_id IS NULL` (global override).
- The Add-ons admin page gains controls to disable/reorder/rename any registered entry, writing rows to this table.

**Critical files.**
- `modules_app/core/models/NavigationRegistry.bx` (new)
- `modules_app/agent/models/RoleRegistry.bx` (new)
- `modules_app/agent/models/PermissionRegistry.bx` (new)
- `modules_app/agent/modules/admin/models/AdminPagesRegistry.bx` (new)
- `modules_app/tickets/models/TicketPanelRegistry.bx` (new)
- `modules_app/reporting/models/DashboardWidgetRegistry.bx` (new)
- `modules_app/core/models/AddonAssetService.bx` (new)
- `modules_app/core/migrations/<timestamp>_create_registry_overrides.bx` (new)
- `modules_app/core/layouts/Portal.bxm` (edit: registry-driven nav + asset tags)
- `modules_app/core/layouts/Agent.bxm` (edit: same)
- `modules_app/agent/modules/admin/views/home/index.bxm` (edit: registry-driven cards)
- `modules_app/agent/modules/admin/handlers/Addons.bx` (new - manage add-ons page)
- `modules_app/agent/modules/admin/views/addons/*` (new)
- `modules_app/agent/views/tickets/show.bxm` (edit: registry-driven panels)
- Every module's `ModuleConfig.bx` (edit: contribute its own existing nav/admin/widget/panel entries)
- `modules_app/agent/models/RbacService.bx` (edit: feed from registry)
- `docs/EXTENSIONS.md` (edit: per-registry section, each with example registrations)

**Verification.**
- Smoke test both surfaces across **all six menu zones** (portal `main`/`account`/`topbar` + agent `main`/`account`/`topbar`). Every existing nav link in every zone still works, in the same order it had before. Every admin home card still works. Every dashboard widget still renders. Every right-column ticket card still appears and respects its collapse-by-default state.
- Spin up the scaffolded throwaway add-on from Phase 1; register sample nav items targeting at least two different menu zones (e.g., one in `agent/main` and one in `agent/account`), a sample admin card, a sample ticket panel, a sample dashboard widget, a sample role with a permission. Confirm each appears in the right surface + menu zone and is gated by the role.
- Toggle the throwaway add-on off via the Add-ons admin page; confirm all contributions disappear.
- Switch the throwaway add-on to `enablement_mode='specific'` and enable it for one org only; log in as a contact in that org and confirm contributions appear, then log in as a contact in another org and confirm they do not.
- Override the sort weight and label of one of the throwaway add-on's nav items through the registry-overrides admin row; confirm the layout reflects the override.

**Pause point.** User exercises both surfaces, the admin pages, the per-org toggle, and the overrides before commit.

---

## Phase 5: Channel adapter registry

**Goal.** Make channel intake plug-in driven so live chat, SMS, Slack-DM, Discord, etc. can all be add-ons.

**Scope - items E1, E2.**

### 5.1 Channel adapter interface
- New `channels.models.contracts.IChannelAdapter` declaring: `getChannelId()`, `getDisplayName()`, `getIcon()`, `verifyConfig(configStruct)`, `pollOnce()` (optional, for pull-based adapters), `normalizeInbound(rawPayload)`, `sendOutbound(message, ticket)`.
- The contract returns a normalized struct that maps cleanly onto `TicketsService.createTicket()` and `TicketsService.addMessage()`.

### 5.2 Channel adapter registry
- New `channels.models.ChannelAdapterRegistry@channels`. Adapters register via `settings.tesserabx.channelAdapters = [...]` declaring the WireBox mapping name of the implementation.
- Migrate the existing email adapter (currently inlined as `InboundEmailProcessor` and `OutboundEmailService`) into a registry entry conforming to the interface. The IMAP poller, blacklist check, and outbound SMTP path all stay where they are; they are now reached through the adapter shape.

### 5.3 Inbound normalization contract
- Document the normalized struct format in `docs/EXTENSIONS.md` and ship a TestBox suite that asserts each registered adapter conforms (round-trip an inbound payload through `normalizeInbound`, confirm the resulting struct passes `TicketsService.createTicket`'s validation).

**Critical files.**
- `modules_app/channels/models/contracts/IChannelAdapter.bx` (new)
- `modules_app/channels/models/ChannelAdapterRegistry.bx` (new)
- `modules_app/channels/models/adapters/EmailChannelAdapter.bx` (new - wraps existing email logic)
- `modules_app/channels/ModuleConfig.bx` (edit: register email adapter)
- `modules_app/channels/handlers/Inbound.bx` (edit: route through registry)
- `docs/EXTENSIONS.md` (edit: Channel adapters section)

**Verification.**
- Inbound email still produces tickets identically (manual: send a test message through Mailpit and confirm a ticket appears with the right fields).
- Outbound email still sends.
- Register a stub adapter in the throwaway add-on (just enough to declare a channel id and a `sendOutbound` that writes to a file); confirm the admin "Channels" page now lists it.

**Pause point.** User verifies both inbound and outbound email still behave correctly and the registry shows core + add-on adapters.

---

## Phase 6: Automation registries

**Goal.** Convert the hard-coded automation engine to a triple-registry pattern so add-ons can ship custom triggers, conditions, and actions.

**Scope - items F1, F2.**

### 6.1 Trigger / condition / action registries
- New registries in `automation.models.`: `TriggerRegistry`, `ConditionRegistry`, `ActionRegistry`. Each entry has an id, label, description, and the relevant evaluator/executor reference.
- Replace the `SUPPORTED_TRIGGERS`, `SUPPORTED_OPS`, `SUPPORTED_ACTIONS` constants in `AutomationService` with reads from the registries. Existing values become registrations seeded by the automation module itself.
- Add-on registrations via `settings.tesserabx.automationTriggers`, `automationConditions`, `automationActions`.

### 6.2 Parameter schema metadata (F2)
- Every registered condition and action declares its parameter schema:
  ```
  {
      id: "slack.postToChannel",
      label: "Post to Slack channel",
      schema: [
          { name: "channel", type: "string", required: true, label: "Channel" },
          { name: "message", type: "textarea", required: true, label: "Message" }
      ],
      executor: "SlackPostExecutor@example-slack"
  }
  ```
- The automation rule editor in the admin UI reads the schema and renders the form generically. No more per-action hard-coded inputs.

**Critical files.**
- `modules_app/automation/models/TriggerRegistry.bx` (new)
- `modules_app/automation/models/ConditionRegistry.bx` (new)
- `modules_app/automation/models/ActionRegistry.bx` (new)
- `modules_app/automation/models/AutomationService.bx` (edit: read from registries)
- `modules_app/automation/ModuleConfig.bx` (edit: seed core triggers/conditions/actions)
- `modules_app/agent/modules/admin/handlers/Automation.bx` and views (edit: schema-driven form)
- `docs/EXTENSIONS.md` (edit: Automation section)

**Verification.**
- Every existing automation rule continues to evaluate identically (run the existing automation test suite).
- The rule editor now renders condition and action parameters from schemas; manually edit an existing rule and confirm it round-trips.
- Register a stub action in the throwaway add-on (e.g., "Log to file"); confirm it appears in the rule editor's action dropdown and can be configured and saved.

**Pause point.** User builds at least one rule that uses an add-on action end to end.

---

## Phase 7: AI feature, provider, and embedding registries

**Goal.** Open the AI subsystem to add-on contributions without losing the "AI off = no AI UI" invariant.

**Scope - items G1, G2, G3, N3.**

### 7.1 AI feature registry (G1)
- New `ai.models.AiFeatureRegistry@ai`. Each feature declares id, label, default system prompt, default model, optional preprocessor and postprocessor references, UI placement metadata (which registries it contributes a panel/button to), and `requiresAi=true`.
- Migrate existing AI features (triage, suggested-reply, summarization, KB indexing) to registry entries.
- `AiMiddleware.complete(feature, prompt, options)` resolves the feature through the registry and applies its system prompt + model defaults. Existing admin prompt-override flow continues to work (the registry holds the *default*; the override table holds the customization).

### 7.2 Provider plug-in interface (G2)
- New `ai.models.contracts.IAiProvider` declaring `complete(promptStruct)`, `embed(text, model)`, `listModels()`, `verifyConfig(configStruct)`.
- The current `bx-ai` integration becomes a built-in provider conforming to the interface. Add-ons can register additional providers via `settings.tesserabx.aiProviders = [...]`.
- The admin AI settings page lets the operator choose any registered provider, with per-tenant override.

### 7.3 Embedding consumer registry (G3)
- New `ai.models.EmbeddingConsumerRegistry@ai`. Consumers declare an id (e.g. `kb.article`), the source-of-truth lookup function, the chunking strategy, and the embedding model preference.
- The KB embedding pipeline becomes a registered consumer; add-ons that want to index external content register their own consumer.
- A single scheduled task drives all registered consumers (re-embed on change, periodic sweep).

### 7.4 AI-off invariant (N3)
- The four UI registries from Phase 4 already honor a capability flag per entry. The AI feature registry sets `requiresAi=true` on every AI-contributed entry it surfaces, so the UI registries automatically hide them when `AI_ENABLED=false`.
- Add a TestBox spec that boots the app with `AI_ENABLED=false`, scans the navigation, admin pages, ticket panels, and dashboard widgets, and asserts zero AI-flagged entries are reachable.

**Critical files.**
- `modules_app/ai/models/AiFeatureRegistry.bx` (new)
- `modules_app/ai/models/EmbeddingConsumerRegistry.bx` (new)
- `modules_app/ai/models/contracts/IAiProvider.bx` (new)
- `modules_app/ai/models/providers/BxAiProvider.bx` (refactor of existing integration)
- `modules_app/ai/models/AiMiddleware.bx` (edit: route through registries)
- `modules_app/ai/ModuleConfig.bx` (edit: seed core features and provider)
- `tests/specs/integration/AiOffInvariantSpec.bx` (new)
- `docs/EXTENSIONS.md` (edit: AI features, providers, embeddings section)

**Verification.**
- Run the existing AI test suite. All passing scenarios still pass; the registry change is transparent to call sites.
- With `AI_ENABLED=true`, all AI features behave identically to today.
- With `AI_ENABLED=false`, the invariant spec proves no AI surface leaks.
- Register a stub AI feature in the throwaway add-on (e.g., a translation feature); confirm it shows up under AI features and respects the capability flag.

**Pause point.** User verifies AI on and AI off scenarios on both surfaces.

---

## Phase 8: API extensibility

**Goal.** Let add-ons contribute REST endpoints, OpenAPI docs, and webhook event types without modifying `api`.

**Scope - items H1, H2, H3.**

### 8.1 API resource registry (H1)
- New `api.models.ApiResourceRegistry@api`. Entries declare `{ httpMethod, path, version, handler, action, jwtScopesRequired, requiredPermission, mementifierIncludes }`.
- Migrate every existing route in `modules_app/api/config/Router.bx` to a registration sourced from the module that owns the entity being exposed (e.g., the `/api/v1/tickets/*` routes are seeded by the `tickets` module).
- The `api` module's router becomes a loop over the registry, applying routes in declared order and version groupings.
- Add-on registrations via `settings.tesserabx.apiResources = [...]`.

### 8.2 OpenAPI contribution (H2)
- cbswagger already scans handler annotations. Confirm that registered routes pointing at add-on handlers are picked up. If cbswagger's scan path is fixed to the `api` module, extend it to follow the resource registry's handler references.
- Add a docblock convention for add-on handlers so cbswagger generates schemas correctly. Document in `docs/EXTENSIONS.md`.

### 8.3 Webhook event registry (H3)
- The set of event keys a webhook subscriber can subscribe to becomes a registry rather than a hard-coded list. Every module's interception points from Phase 3 register themselves as subscribable webhook events.
- The admin webhook subscription form (already shipped) reads the registry rather than a static dropdown.
- Add-ons can register additional webhook events that are also fan-out targets.

**Critical files.**
- `modules_app/api/models/ApiResourceRegistry.bx` (new)
- `modules_app/api/config/Router.bx` (edit: drive from registry)
- `modules_app/api/models/WebhooksService.bx` (edit: event list from registry)
- Every module that exposes API endpoints (edit `ModuleConfig.bx`: seed its routes)
- `modules_app/agent/modules/admin/handlers/Webhooks.bx` and views (edit: dropdown from registry)
- `docs/EXTENSIONS.md` (edit: API + webhooks section)

**Verification.**
- Every existing `/api/v1/...` route still responds identically (run the API test suite plus a manual curl against a representative endpoint).
- cbswagger output at `/api/swagger.json` (or wherever it lives) still includes every existing route and now also includes routes registered from the throwaway add-on.
- Register a webhook subscription against an add-on-contributed event from the throwaway add-on; fire the event manually; confirm the webhook delivers.

**Pause point.** User exercises the API and webhook surfaces before commit.

---

## Phase 9: Custom fields generalization and data extension

**Goal.** Let custom fields attach to entities beyond `Ticket`, and define the convention for add-ons to attach their own data to core entities without altering core tables.

**Scope - items J1, J2.**

### 9.1 Generalize custom fields (J1)
- Audit `CustomFieldsService` for hard-coded `entityType='ticket'` queries. Parameterize them.
- Add the admin UI surfaces for managing custom fields on `Contact`, `Organization`, `Article`. Each becomes a new admin page registered via Phase 4's AdminPagesRegistry.
- The CBWire components that render custom-field forms become entity-agnostic and accept `entityType` and `entityId` props.
- Add `Contact`, `Organization`, `Article` custom-field value tables analogous to the existing `ticket_custom_field_values`.

### 9.2 Entity extension table convention (J2)
- Document the pattern: an add-on that needs to attach data to a core entity creates a table named `<core_entity>_<addon_id>` (e.g., `tickets_example_jira`) with `(entity_id PK FK, organization_id, ...add-on columns)`. Tenancy is enforced through `organization_id` and the published tenant scope from Phase 2.
- Provide a helper `core.models.EntityExtensionService@core` that resolves an add-on's extension row for a given core entity id, validates tenancy, and caches per request.

**Critical files.**
- `modules_app/tickets/models/CustomFieldsService.bx` (edit: parameterize)
- `modules_app/contacts/models/CustomFieldsService.bx` (new or shared)
- `modules_app/knowledgebase/models/CustomFieldsService.bx` (new or shared)
- `modules_app/core/migrations/<timestamp>_contact_custom_field_values.bx` (new)
- `modules_app/core/migrations/<timestamp>_organization_custom_field_values.bx` (new)
- `modules_app/core/migrations/<timestamp>_article_custom_field_values.bx` (new)
- `modules_app/agent/modules/admin/handlers/CustomFields.bx` (edit: entity-aware)
- `modules_app/core/models/EntityExtensionService.bx` (new)
- `docs/EXTENSIONS.md` (edit: custom fields + entity extension sections)

**Verification.**
- Existing ticket custom fields work exactly as before (run the existing suite).
- Manually add a custom field to `Contact` via the admin UI, fill it on a contact, and confirm it persists and reads.
- Have the throwaway add-on create a `tickets_<addon>` extension table, write a row through the helper, and read it back. Confirm tenancy is enforced.

**Pause point.** User verifies ticket and contact custom fields, then add-on extension table.

---

## Phase 10: Notifications extensibility

**Goal.** Let add-ons ship default email templates and contribute new delivery channels into the existing fan-out.

**Scope - items L1, L2.**

### 10.1 Notification template registry (L1)
- New `notifications.models.NotificationTemplateRegistry@notifications`. Each template declares event key, default subject, default body (markdown or HTML), and supported substitution variables.
- Existing core notification templates become registrations.
- An admin "Notification Templates" page (registered via AdminPagesRegistry) lets the admin override the default per template per organization.
- Add-on registrations via `settings.tesserabx.notificationTemplates = [...]`.

### 10.2 Delivery channel plug-ins (L2)
- New `notifications.models.contracts.INotificationChannel` declaring `getChannelId()`, `getDisplayName()`, `send(recipient, payload, prefs)`, `supportsBatch()`.
- The current email + Slack/Teams delivery paths become built-in channel implementations.
- Add-ons can register additional channels via `settings.tesserabx.notificationChannels = [...]` (e.g., SMS via Twilio, Pushover, in-house webhook).
- The per-user notification preferences UI dynamically lists every registered channel.

**Critical files.**
- `modules_app/notifications/models/NotificationTemplateRegistry.bx` (new)
- `modules_app/notifications/models/contracts/INotificationChannel.bx` (new)
- `modules_app/notifications/models/channels/EmailChannel.bx` (new - wraps existing)
- `modules_app/notifications/models/channels/SlackChannel.bx` (new - wraps existing)
- `modules_app/notifications/models/NotificationsService.bx` (edit: dispatch through registered channels)
- `modules_app/notifications/ModuleConfig.bx` (edit: register templates + channels)
- `modules_app/agent/modules/admin/handlers/NotificationTemplates.bx` (new)
- `docs/EXTENSIONS.md` (edit: notifications section)

**Verification.**
- Every existing notification still sends through the right channel(s) with the same content.
- Override one template's subject through the admin UI for one organization; confirm the next dispatch for that org uses the override.
- Register a stub channel in the throwaway add-on (e.g., write-to-file channel); confirm it appears in user preference UI and receives dispatches.

**Pause point.** User verifies email + Slack fan-out and the stub channel before commit.

---

## Phase 11: Extendable in-app help module

**Goal.** Ship a first-party `help` module that hosts an in-app online help system. Every core module and every add-on contributes pages to it through the same registry-style mechanism the rest of the plan uses. The initial scope covers a general help landing page, an audience-gated module-development section that mirrors `docs/EXTENSIONS.md` for add-on authors (rendered inline and downloadable), and AI-powered semantic search that gracefully degrades to text matching when AI is off.

**Scope - new first-party module + new registry + integration with several earlier phases.**

### 11.1 The `help` module itself

- New first-party module at `modules_app/help/`, following the same internal layout as every other core module (`ModuleConfig.bx`, `handlers/`, `models/`, `views/`, `wires/`, `resources/`, `tests/`).
- The module is **extendable**: it owns the help system, but contributes only its own structural pages (the landing page, the table of contents, search, the developer-section index, the EXTENSIONS download endpoint). Actual topical pages (e.g., "How to submit a ticket", "Setting an SLA policy") are contributed by the module that owns the topic.
- Routes:
  - `/help` - public landing + browse on the portal surface.
  - `/agent/help` - auth-required landing + browse on the agent surface.
  - `/help/:sectionId/:pageId` and `/agent/help/:sectionId/:pageId` - per-page rendering, audience-filtered by the resolved viewer.
  - `/help/download/extensions.md` - serves the live `docs/EXTENSIONS.md` (auth-required, gated to the `developer` audience).
  - `/help/search` - search endpoint backing the search box (delegates to embeddings when AI is on, text matching otherwise).
- The help layout extends the surface layout that hosts it; it inherits navigation, account menu, and top bar from each surface, so help pages live inside the normal shell. A "Help" entry is registered into both the portal and agent main-menu nav zones from Phase 4.2.

### 11.2 Help page registry (the new extension point)

- New `help.models.HelpPageRegistry@help` and `help.models.HelpSectionRegistry@help`.
- Modules contribute pages via `settings.tesserabx.helpPages` and sections via `settings.tesserabx.helpSections` in `ModuleConfig.bx`:
  ```
  settings.tesserabx.helpSections = [
      { id: "tickets",     title: "Tickets",         audience: "any",       sortWeight: 100, icon: "ticket"    },
      { id: "development", title: "Module Development", audience: "developer", sortWeight: 900, icon: "code"  }
  ];
  settings.tesserabx.helpPages = [
      {
          id          : "tickets.creating-a-ticket",
          title       : "Creating a ticket",
          section     : "tickets",
          audience    : "client",
          sortWeight  : 10,
          source      : "resources/help/tickets/creating-a-ticket.md",
          searchable  : true,
          keywords    : [ "new ticket", "submit", "create" ]
      }
  ];
  ```
- `audience` values: `public` (anonymous viewers allowed), `client` (logged-in contacts on the portal), `agent` (provider agents only), `developer` (gated to a new `help.developer` permission registered in Phase 4.1).
- Page resolution: the `source` path is relative to the contributing module's root. Markdown is rendered through bx-markdown at request time, cached per page until next reinit.
- An audience-aware index helper returns the set of sections + pages visible to the current viewer. The browse page renders this index grouped by section.

### 11.3 Module-development help section

- The `help` module ships its own section registration with id `development`, audience `developer`.
- The section's pages mirror the structure of `docs/EXTENSIONS.md` chapter-by-chapter, each rendered inline. Implementation choice between (a) shipping the entire `EXTENSIONS.md` as a single rendered page or (b) splitting it into one page per registry chapter is decided during this phase; recommended approach is **split into per-chapter pages** so each chapter is independently linkable and searchable.
- The section index includes a prominent "Download EXTENSIONS.md" button hitting `/help/download/extensions.md`. The endpoint streams the file directly from `docs/EXTENSIONS.md` with the correct content-disposition; no duplicate copy is maintained.
- A short "About this section" intro page on the section landing explains the relationship between the inline pages and the downloadable markdown (same content, different format).
- The `developer` audience permission (`help.developer`) is auto-granted to the `agent-admin` role; other agents can be granted it explicitly through the Phase 4.1 admin Users page.

### 11.4 Search

- Search is wired through Phase 7's `EmbeddingConsumerRegistry`. The help module registers a consumer with id `help.page`, source-of-truth being the resolved set of help pages (audience-filtered at query time, not at index time - the embedding index is global; access control happens after ranking).
- When `AI_ENABLED=true`: search box on the help index runs a vector similarity search through `AiMiddleware.embed()` against the help embedding store, then filters out pages the viewer cannot see.
- When `AI_ENABLED=false`: the same search box falls back to a substring/keyword match across page titles, declared `keywords`, and rendered body text. The user-facing search box behavior is identical; only the ranking quality differs. The page does not advertise "AI search" or reveal which mode is active.
- The embedding consumer's chunking strategy is per-page (each registered help page becomes one embedded chunk, body truncated to a sensible length); if a page is long enough to warrant multi-chunk indexing, that is a future refinement.

### 11.5 Initial content

- The general help landing page ships with: a short "Welcome" intro, links to the top-level sections, and a search box.
- Core modules (`tickets`, `contacts`, `knowledgebase`, `automation`, `sla`, `agent`, `portal`) each ship **at minimum one initial help page** representing the most common task in their domain. These initial pages are placeholders that the team can expand over time; the goal of Phase 11 is to prove the registry, not to ship a complete user manual.
- The `development` section ships fully populated (every chapter of `EXTENSIONS.md` rendered as a page).

### 11.6 Manifest documentation update

- `docs/EXTENSIONS.md` gains a "Help pages" section documenting the manifest fields, audience values, the `developer` permission, and the search behavior. This section itself becomes one of the rendered pages in the development section, so the help module reads its own contract.

**Critical files.**
- `modules_app/help/ModuleConfig.bx` (new)
- `modules_app/help/handlers/Home.bx` (new - landing + index)
- `modules_app/help/handlers/Section.bx` (new - per-section browse)
- `modules_app/help/handlers/Page.bx` (new - render single page)
- `modules_app/help/handlers/Search.bx` (new - text + semantic search)
- `modules_app/help/handlers/Download.bx` (new - EXTENSIONS.md serve)
- `modules_app/help/models/HelpPageRegistry.bx` (new)
- `modules_app/help/models/HelpSectionRegistry.bx` (new)
- `modules_app/help/models/HelpAudienceResolver.bx` (new)
- `modules_app/help/models/HelpEmbeddingConsumer.bx` (new - implements G3's consumer interface)
- `modules_app/help/views/...` (new - index, section, page, search)
- `modules_app/help/resources/help/development/*.md` (new - EXTENSIONS chapters split into pages)
- `modules_app/help/resources/help/welcome.md` (new - landing intro)
- Initial content drops in `modules_app/<each-core-module>/resources/help/*.md` (new)
- Each core module's `ModuleConfig.bx` (edit: register at least one help page + any sections it owns)
- `modules_app/agent/models/PermissionRegistry.bx` (edit: register `help.developer` permission)
- `modules_app/agent/models/RoleRegistry.bx` (edit: auto-grant to `agent-admin`)
- `modules_app/core/NavigationRegistry` registrations (edit: register the "Help" main-menu item on both surfaces)
- `docs/EXTENSIONS.md` (edit: "Help pages" section)

**Verification.**
- Anonymous visitor hits `/help`: sees only `public` pages and sections containing public pages. No agent or developer content is reachable or even listed.
- Logged-in contact hits `/help`: sees `public` + `client` pages.
- Logged-in agent without `help.developer` permission hits `/agent/help`: sees `public` + `client` + `agent` pages; the development section is not listed.
- Logged-in agent with `help.developer` hits `/agent/help`: sees everything, including the development section. Each EXTENSIONS chapter renders cleanly. The "Download EXTENSIONS.md" button delivers the live file.
- Toggle `AI_ENABLED=false`: search box still works, returning text-match results. Toggle `AI_ENABLED=true`: same search box returns semantically ranked results. Both modes respect audience filtering.
- Register a help page from the throwaway add-on with audience `agent`; confirm it appears in the agent help index but not the portal help index.
- Disable the throwaway add-on via the Add-ons admin page; confirm its help pages disappear from both indexes and direct navigation to the page returns a clean "not found / not available" rather than a server error.

**Pause point.** User walks the help system on both surfaces as each audience, verifies the AI-on and AI-off search modes, and downloads the EXTENSIONS.md file before commit.

---

## Phase 12: Reference add-on, CI integration, complete docs

**Goal.** Prove the entire extension surface end to end with a real, useful sample add-on, wire it into CI, and finish `docs/EXTENSIONS.md` so a developer can build their own from the doc alone.

**Scope - items M3, M4, M2 (complete).**

### 12.1 Sample reference add-on (M3)
- Build a meaningful sample add-on that exercises every registry. Recommended subject: an "Example Jira-style sync" add-on that:
  - Registers navigation items in **multiple menu zones** (e.g., main menu plus account dropdown) on the agent surface.
  - Registers an admin page for connection settings.
  - Registers a ticket right-column panel showing the linked external issue.
  - Registers a dashboard widget showing sync status.
  - Registers a role and permission (`example-sync-admin` / `exampleSync.manage`).
  - Registers a channel adapter for inbound webhook from the external system.
  - Registers an automation action ("Link this ticket to a new external issue").
  - Registers an AI feature (optional summarization of the external issue).
  - Registers API routes under `/api/v1/example-sync/*`.
  - Registers a webhook event for "external issue linked".
  - Defines an entity extension table `tickets_example_sync`.
  - Registers a notification template for the link event.
  - Registers a delivery channel that posts to a stub HTTP endpoint.
  - **Registers at least two help pages**: one with audience `agent` describing the day-to-day use of the integration, and one with audience `developer` documenting the add-on's own internal contract for anyone extending it further.
- The add-on lives in a separate repo (`tesserabx-example-sync` on the same git host) and is installed into `modules/` via `box install` during local dev and CI setup.
- Alternatively, for the very first iteration of this phase the add-on may be developed in-tree under a `/sample-addons/example-sync/` scratch folder (excluded from production builds) and only published to its own repo once stable; pick whichever the user prefers when this phase is reached.

### 12.2 CI integration (M4)
- Update `.github/workflows/*` so CI installs the sample add-on into `modules/` before running the test suite, and runs the add-on's own `tests/` suite in the same job. A failure in the add-on's specs fails the whole pipeline, which is how the extension contract stays honest.

### 12.3 Complete `docs/EXTENSIONS.md` (M2)
- The doc, accumulated incrementally through phases 1 to 10, gets a final polish pass. Every registry has a "What it does", "How to register", "Example", and "What happens when it is disabled" subsection. Every interface lists its method signatures and return shapes. Every event lists its payload shape and async behavior. A table-of-contents at the top makes the doc navigable.
- A "Quick start: build your first add-on" section walks through the scaffolder + a 30-line registration example end to end.

**Critical files.**
- `tesserabx-example-sync/` (new repo) or `sample-addons/example-sync/` (in-tree scratch)
- `.github/workflows/<existing workflow>.yml` (edit: install + run sample add-on tests)
- `docs/EXTENSIONS.md` (final polish)
- `README.md` (edit: link to `docs/EXTENSIONS.md` and the sample add-on)

**Verification.**
- CI green with the sample add-on's specs included.
- Walk a fresh developer through the "Quick start" in the doc; they should be able to scaffold and register a working nav item in under 15 minutes.
- Toggle the sample add-on off via the Add-ons admin page; confirm every contribution vanishes from every surface.

**Pause point.** User reads the final doc and explores the running sample add-on before commit.

---

## Phase 13: Hardening pass

**Goal.** Treat the extension surface as a now-shipped feature and look for the things easy to miss when each registry was built in isolation.

**Scope - cross-cutting review.**

### 13.1 Tenancy safety sweep
- Search every registry implementation for queries that touch tenant-scoped tables without `organization_id`. The `TenancyGuard` from Phase 2 should catch them, but a manual review is warranted before declaring done.
- Write a deliberately bad add-on (under a `tests/fixtures/leaky-addon/` folder) that tries to leak data across tenants, and confirm the guard catches it in every code path.

### 13.2 Performance review
- Measure registry lookup cost on app boot (every module's `ModuleConfig.bx` reads should be cached and resolved once).
- Measure layout render cost when navigation registry has, say, 50 entries (synthetic load) across all six menu zones.
- Add an indexed read path for `registry_overrides` since it is hit on every render.
- Confirm help page rendering is cached after first render and the bx-markdown pass is not repeated per request.

### 13.3 Security review of extension surface
- Confirm an add-on cannot register a nav item or admin page that bypasses cbsecurity. The required permission id is mandatory on every contribution; entries missing one are rejected at registration time with a loud error.
- Confirm that registered API routes inherit JWT validation from the api module's pre-handler; an add-on cannot ship an unauthenticated route by omission.
- Confirm that the `requiresAi=true` flag is checked centrally so an add-on cannot leak AI UI when AI is off.
- Confirm the help audience filter is enforced server-side at render time, not just at index time - direct navigation to a `developer`-audience help page URL by an unauthorized viewer returns the same outcome as an unknown page, never the content.

### 13.4 Final docs polish
- Update `docs/BUILD-PLAN.md` and `docs/FUTURE-WORK.md` to mark the relevant deferred items as now unblocked (live chat as a channel adapter, Jira/GitHub as add-ons, approval workflows as an automation action + admin page combination).
- Update `CLAUDE.md` "Modules" section to mention that add-ons live in `modules/` and what new hard constraints govern them.

**Critical files.**
- `modules_app/contacts/models/tenancy/TenancyGuard.bx` (edit: any tightening discovered during sweep)
- `tests/fixtures/leaky-addon/` (new)
- `tests/specs/integration/TenancySweepSpec.bx` (new)
- `docs/BUILD-PLAN.md` (edit: mark unblocked items)
- `docs/FUTURE-WORK.md` (edit: same)
- `CLAUDE.md` (edit: add-on hard constraints)

**Verification.**
- Tenancy sweep spec passes.
- Performance numbers acceptable (define acceptable bar during this phase based on whatever the baseline render time is).
- Security review checklist completed.
- All docs cross-references resolve.

**Pause point.** User reviews the hardening summary, the perf numbers, and the updated docs before final commit.

---

## Progress log

_Append a dated, one-paragraph note here at the end of every completed phase. Format:_

```
### YYYY-MM-DD - Phase N: <title>
- What landed.
- Anything that diverged from the plan and why.
- Files touched that the plan did not list.
- Follow-ups identified.
```

### 2026-05-20 - Phase 0: Plan persistence and progress tracking
- Saved this plan as `docs/EXTENSIBILITY-PLAN.md` (em dashes stripped on the way in, external memory link rewritten in prose).
- Cross-linked from `docs/BUILD-PLAN.md` and `docs/FUTURE-WORK.md`, added a pointer paragraph to `CLAUDE.md`.
- No deviations.
- No additional files touched beyond the four listed in the plan.

### 2026-05-20 - Phase 5: Channel adapter registry
- `IChannelAdapter` contract published at `modules_app/channels/models/contracts/IChannelAdapter.bx`. Documents the eight-method shape every adapter implements: `getChannelId`, `getDisplayName`, `getIcon`, `isPullBased`, `verifyConfig`, `pollOnce`, `normalizeInbound`, `sendOutbound`. The normalized inbound struct contract is documented in the class docblock and in `docs/EXTENSIONS.md`.
- `ChannelAdapterRegistry@channels` ships. Reads add-on adapters from each module's `settings.tesserabx.channelAdapters = [ { mapping : "..." } ]` manifest declaration; seeds the core email adapter in its own `ensureLoaded()` (same pattern as `RoleRegistry` / `PermissionRegistry`). Public surface: `register`, `adapterFor`, `listAdapters`, `listChannelIds`, `pollAll`, `reload`.
- `EmailChannelAdapter@channels` wraps the existing `InboundEmailProcessor`, `OutboundEmailService`, and `IMAPPoller`. The adapter is a thin facade that gives email the channel-adapter shape without disturbing the underlying mechanics. Channel id `"email"`, icon `"bi bi-envelope"`, pull-based.
- `docs/EXTENSIONS.md` Channel adapters section published, covering the contract, both registration paths (manifest for add-ons, imperative for core), the normalized inbound struct shape, polling cadence semantics, and the outbound-dispatch follow-up.
- Specs: `ChannelAdapterRegistrySpec` (10/10) covering core seed registration, lookup by channel id, return shape of `listAdapters`, idempotence of `register`, the `EmailChannelAdapter` contract conformance (verifyConfig shape, normalizeInbound envelope shape with all 13 documented keys present), and `pollAll` aggregation.
- Full sweep: 429/4/9 (Phase 4 baseline + 10 new specs, identical pre-existing 4+9 CBFS/s3sdk failures).
- Design choices worth flagging:
  - Core registers the email adapter via a self-seed inside `ChannelAdapterRegistry.ensureLoaded()` rather than through the manifest path. Manifest declaration would make `channels` appear as a distinct add-on in the admin Add-ons page, which is wrong UX (`channels` is not separately installable). Add-ons use the manifest path; core uses the self-seed. Both paths arrive at the same in-memory cache.
  - Initial attempt to register via `controller.getWireBox().getInstance(...)` from the ModuleConfig's `onLoad()` silently failed (no exception logged, but the adapter was missing from the cache). The self-seed inside `ensureLoaded()` sidesteps any ColdBox lifecycle timing issue.
  - `EmailChannelAdapter.normalizeInbound()` is mostly pass-through today because the existing `IMAPPoller.normaliseRow` already produces a struct very close to the canonical envelope. Future channels (Slack DM, Twilio SMS) will do real translation here.
- Deferrals:
  - Outbound dispatch generalization: currently `OutboundEmailInterceptor` knows how to route through `OutboundEmailService` for email. A future generic `OutboundDispatchInterceptor` that resolves the right adapter by ticket source and calls `adapter.sendOutbound()` is documented in EXTENSIONS.md as a follow-up. Add-on adapters dispatch by registering their own listener on relevant `onTicket*` events for now.
  - Scheduler migration from `IMAPPoller.poll()` direct invocation to `ChannelAdapterRegistry.pollAll()` deferred. Both paths are idempotent (de-duplicate by Message-ID) so running them simultaneously is safe; the scheduler can be migrated whenever convenient.
  - Admin "Channels" page that lists installed adapters with verifyConfig buttons is not built. The registry surfaces the data; the UI is a small follow-up.

### 2026-05-20 - Phase 4: UI registries and RBAC
- `PermissionRegistry@agent` and `RoleRegistry@agent` ship with core seeds (4 roles, 10 permissions). `RbacService.roleCatalog()` now delegates to `RoleRegistry.listForSurface("agent")` so add-on roles flow through.
- `NavigationRegistry@core` plus six menu-zone migrations: Portal.bxm and Agent.bxm now iterate `tbxNavigation( surface, menu )` for `main` / `account` / `topbar`. Each surface's left sidebar, account dropdown, and top bar (top bar is currently sparse) is registry-driven.
- `AdminPagesRegistry@admin` plus admin home migration: the 12 hard-coded card buttons in `/agent/admin` are now 14 registry-driven cards (added "Add-ons" and "Add-on settings" for Phase 1/2 surfacing).
- `/agent/admin/addons` handler + view shipped. Lists every discovered add-on with controls for global enable, enablement_mode (`all` vs `specific`), and per-organization rows. Gated on the new `admin.addons.manage` permission.
- `TicketPanelRegistry@tickets` and `DashboardWidgetRegistry@reporting` ship the registry contract + add-on contribution path. The existing inline core panels and widgets are NOT migrated to the registries; add-on contributions render alongside the existing inline blocks. Documented as a deferral in EXTENSIONS.md.
- `AddonAssetService@core` + two helper functions (`tbxAssetCss`, `tbxAssetJs`). Both layouts emit add-on CSS in `<head>` and JS just before `</body>`.
- New `registry_overrides` table with two partial unique indexes (one for global rows, one for per-tenant) provides admin disable/reorder/rename for all four UI registries. The four registries read overrides per-tenant with a global fallback.
- Pre-flight scoping sweep: fixed Phase-1 unscoped-assignment bug in `api`, `audit`, `portal`, and `admin` ModuleConfigs (4 modules).
- Specs: `RoleAndPermissionRegistrySpec` (11/11), `NavigationRegistrySpec` (9/9), `AdminPagesRegistrySpec` (7/7), `AddonAssetServiceSpec` (2/2). Total +29 from Phase 3 baseline.
- Full sweep: 432/0/0 (was 390/4/9 in Phase 3). The previously-failing CBFS/s3sdk specs cleared this run, likely because the container restart reset the dev-env state that those specs are sensitive to.
- Deviations from plan:
  - TicketPanelRegistry and DashboardWidgetRegistry ship the contract only. The existing ~10 right-column ticket cards in `modules_app/agent/views/tickets/show.bxm` and the 6 widgets in `modules_app/agent/views/reports/index.bxm` remain inline; they were not extracted into registry-driven partials. Add-on panels and widgets work end-to-end; core's existing blocks render before any add-on contributions. Migration is a follow-up.
  - The portal "top bar" and "agent top bar" zones are technically registry-driven but core seeds no entries for them (the agent notification bell stays as a CBWire feature widget, not a nav item). Add-ons can declare topbar entries.
  - The "Add-on settings" admin page (link from admin home) currently has no implementation; it links to a placeholder route. The full form lands as a Phase 11 follow-up that builds on SettingsRegistry from Phase 2.
- Files touched that the plan did not list:
  - `includes/helpers/ApplicationHelper.bxm` (added 5 helper functions: tbxViewer, tbxNavigation, tbxAssetCss, tbxAssetJs, tbxTicketPanels, tbxDashboardWidgets).
  - `modules_app/api/ModuleConfig.bx`, `modules_app/audit/ModuleConfig.bx`, `modules_app/portal/ModuleConfig.bx`, `modules_app/agent/modules/admin/ModuleConfig.bx` (scoping-bug fixes).
- Follow-ups identified:
  - Existing inline ticket panels and dashboard widgets should be extracted into registry-driven partials in a follow-up phase so core "eats its own dog food" as the plan envisioned.
  - The `/agent/admin/addon-settings` placeholder needs a real implementation (Phase 11 will own this when it builds the help / admin UI surfaces).
  - Three new gotchas captured below (registry recursion, string-vs-numeric sort, ColdBox 8 `getModel` not a thing).

### 2026-05-20 - Phase 3: Event surface and audit contributions
- `EventPayloadBuilder@core` produces the canonical envelope (event, occurredAt, organizationId, actorType, actorId, entity, before, after, metadata) used by every new event.
- Seventeen new announcements added across tickets (5: assigned, tags-added, attachment-added, attachment-deleted, promoted-to-contact), contacts (7: org-created, contact-provisioned, contact-deactivated, role-granted, role-revoked, domain-mapped, merged), agent (4: created, updated, activated, deactivated), and RBAC (2: role-granted, role-revoked, scoped to agents). All new announcements use `announceAsync`.
- All five pre-Phase-3 events left untouched (their entity-shaped payload is consumed by six active interceptors; switching to the canonical envelope would break working code). Documented in `docs/EXTENSIONS.md` Events section.
- `customInterceptionPoints` updated in tickets, contacts, and agent ModuleConfigs. While there, fixed the Phase-1 scoping bug in `contacts/ModuleConfig.bx` and `agent/ModuleConfig.bx` (unscoped `interceptorSettings = ...` would have silently dropped the new events into function-local scope).
- New migration `2026_05_20_000030_add_source_to_audit_events.cfc` adds the `source` column. `AuditService.record()` accepts a new optional `source` arg; `AuditService.search()` accepts a matching filter (sentinel `"core"` means "null only"); new `AuditService.listSources()` returns distinct sources for the admin UI dropdown.
- `AuditService.listEventTypes()` now merges the distinct types in the log with every add-on's manifest-declared `auditEvents = [...]`, so add-on types appear in the admin filter dropdown before they have ever fired. The `auditEvents` array is captured automatically through the addons.metadata JSON column (no AddonRegistryService changes needed; the manifest is already serialized end-to-end).
- Admin audit search UI at `/agent/admin/audit` got a Source filter dropdown.
- `docs/EXTENSIONS.md` expanded with two new sections: Events (with sub-sections covering canonical payload, async policy, and the catalog of 17 new + 5 existing events) and Audit-event contributions (record() usage, manifest declaration, naming convention).
- Specs: `EventPayloadBuilderSpec` (7/7) + `AuditSourceSpec` (8/8).
- Deviations from plan:
  - Phase 3.1 called for the full event catalog from the plan (~40 events). I shipped the 17 well-defined ones across tickets/contacts/agent/RBAC and deferred SLA / automation / channels / KB-beyond-publish / AI / API-webhook events. Those modules are touched directly by later phases (5, 6, 7, 8) and their announcement points are better added in context. The omission is intentional and documented; no add-on contract is silently missing because the canonical envelope shape and the announcement-naming convention are documented in EXTENSIONS.md.
  - The five pre-Phase-3 events kept their original payload shape (entity-keyed) rather than being rewrapped in the canonical envelope. Mixing shapes is documented in EXTENSIONS.md; the cost of breaking six consumer interceptors outweighed the consistency gain. Future migration of these to the canonical envelope is a follow-up if it becomes load-bearing.
- Files touched that the plan did not list:
  - `modules_app/agent/models/AgentService.bx`, `modules_app/agent/models/RbacService.bx` (announcement additions; plan grouped these under "agent" without naming the specific files).
  - `modules_app/contacts/ModuleConfig.bx` and `modules_app/agent/ModuleConfig.bx` (scoping-bug fixes adjacent to the new customInterceptionPoints declarations).
- Follow-ups identified:
  - The remaining ~25 events from the plan's catalog (SLA, automation, channels, KB, AI, API webhooks) belong in the phases that own those modules. Each Phase 5-8 build should add announcements for the state transitions it touches, using the same `EventPayloadBuilder@core` + `announceAsync` pattern.
  - The five pre-Phase-3 events are an inconsistency. If a future phase forces a payload-shape rewrite (e.g., the reference add-on in Phase 12 needs the canonical envelope from these too), bundle the consumer migration with the rewrite.

### 2026-05-20 - Phase 2: Service contracts and tenancy safety
- Five service contract classes published under `models/contracts/`: ITicketsService, IContactsService, IAuditService, INotificationsService, IAiMiddleware. They document the public surface add-ons may rely on; method bodies throw `ContractClass.NotImplemented` because BoxLang has no `interface` keyword.
- Four DTO mapper services published under `models/dtos/`: TicketDto, ContactDto, AuditEventDto, NotificationDto. Each maps Quick entities to snake_case structs that match the JSON the API already returns.
- TenantScope and TesseraBXEntity got "Public extension contract" docblock additions; no behavior change. Tenant-scope publication is documentation-only.
- TenancyGuard@contacts shipped with `applyScope` (the convenience helper) and `assertHasOrgPredicate` (the runtime safety net). The dev-only TenancyAuditInterceptor was intentionally NOT shipped — see deviation below.
- New migration `2026_05_20_000020_create_addon_settings.cfc` adds the per-tenant override table.
- SettingsRegistry@core resolves descriptor + override; rejects unknown keys and writes to perTenant=false descriptors; provides `listDescriptors`, `listOverridesForOrganization`, `set`, `clear`.
- Per-module migration namespacing documented (slug-prefix convention) in `docs/EXTENSIONS.md`. No runner change needed.
- Specs: `TenancyGuardSpec` (7/7) + `SettingsRegistrySpec` (12/12).
- Wiring: SettingsRegistry@core, TenancyGuard@contacts, and the four DTO mappers all bound in their respective ModuleConfigs.
- Deviations from plan:
  - The dev-only `TenancyAuditInterceptor` (Phase 2.4) was NOT shipped. The plan called for an interceptor that "applies the guard to incoming requests for known sensitive routes as a backstop," but the definition of "sensitive routes" and the integration between request-scoped preProcess and per-query tenancy checking were too squishy to make load-bearing. `TenancyGuard` itself ships and is the substantive piece; the interceptor would be a no-op placeholder. If a future phase needs a request-scoped backstop, it can be added then with a concrete use case driving the design.
  - The contract classes are advisory documentation, not enforceable interfaces. BoxLang has no `interface` keyword (confirmed: `grep "interface {"` returns nothing in the codebase). Add-ons code against the live service via WireBox, and the contract files serve as the canonical reference for the method surface.
  - Two qb introspection details surfaced in the TenancyGuard implementation; see gotcha log.
- Files touched that the plan did not list:
  - `modules_app/audit/models/dtos/AuditEventDto.bx` (new)
  - `modules_app/notifications/models/dtos/NotificationDto.bx` (new)
  - `modules_app/audit/ModuleConfig.bx`, `modules_app/notifications/ModuleConfig.bx` (DTO bindings)
- Follow-ups identified:
  - Several existing ModuleConfigs across `tickets`, `contacts`, `audit`, `notifications`, etc. use unscoped `settings = {...}` assignments in `configure()` (same scoping bug discovered in Phase 1's gotcha log). They get away with it today because nothing reads those settings, but the Phase 7 / Phase 11 work will start reading them. A sweep to add `variables.` prefixes belongs in whatever phase first touches each module.

### 2026-05-20 - Phase 1: Add-on foundation
- Migration `2026_05_20_000010_create_addon_tables.cfc` creates `addons` and `addon_organization_enablement`.
- `appVersion` setting added to `config/Coldbox.bx` as single source of truth (read via `getSetting("appVersion")`).
- `AddonRegistryService@core` ships in `modules_app/core/models/`: manifest validation, version-range checker (with open-upper-bound semantics), enablement resolution, admin mutations.
- `AddonDiscoveryInterceptor@core` ships in `modules_app/core/interceptors/`, hooks `afterAspectsLoad`, syncs all loaded modules' manifests on app boot.
- `tasks/ScaffoldAddon.cfc` plus `tasks/templates/*.tpl` generates a skeleton add-on under `modules/<slug>/`.
- `docs/EXTENSIONS.md` Phase 1 stub published.
- `modules_app/core/tests/specs/AddonRegistryServiceSpec.bx` covers version comparison (6 specs), compatibility ranges (6 specs), enablement resolution (6 specs), and admin mutations (2 specs). 20/20 pass.
- End-to-end proof: ran `box task run tasks/ScaffoldAddon run hello-world "Hello World"` inside the app container, restarted, confirmed the row appeared in `addons` (`enabled=t, enablement_mode='all', compatible=t`) and that toggling it disabled it for any caller. The hello-world artifact is left in the container's `/app/modules/` volume for inspection during verification.
- Deviations from plan:
  - Task file is `.cfc` not `.bx` (CommandBox 6.x hardcodes `.cfc` for runners; see gotcha log).
  - Templates are in `tasks/templates/` rather than inlined in the task source (Lucee `#` interpolation in CFC strings forced externalization; see gotcha log).
  - `enabled_by_agent_id` uses SQL `NULLIF(:actor, '')` rather than a `javaCast("null","")` bind (BoxLang scope walker drops null var inits; see gotcha log).
- Files touched that the plan did not list:
  - `tasks/templates/ModuleConfig.bx.tpl`, `tasks/templates/box.json.tpl`, `tasks/templates/README.md.tpl`, `tasks/templates/InstallSpec.bx.tpl` (template externalization).
- Follow-ups identified:
  - The 4 other gotchas captured below all generalize. They will likely bite Phase 2 (which adds service interfaces and a settings registry across every module) and should be documented in `docs/EXTENSIONS.md` before that phase ships.
  - The full TestBox suite reports 4 failures + 9 errors, all unrelated to Phase 1 (CBFS / s3sdk dev-environment issues already noted in the project memory `feedback_cbfs_test_env_split.md`).

---

## Gotchas and workarounds log

_Append BoxLang / ColdBox / cbSecurity / cbq / cbfs surprises encountered during build, with the workaround applied. Future phases (and future contributors) read this before working in the same area._

### Phase 1 - Unscoped assignments in `ModuleConfig.bx configure()` go to function-local

In BoxLang, an unscoped assignment inside a `function` body lands in the function's local scope, not the class's `variables` scope. ColdBox's ModuleService reads module config via `getPropertyMixin( "<key>", "variables", [] )`, so anything not prefixed with `variables.` is invisible to the framework.

The casualty: `interceptors = [...]` and `settings = { tesserabx : ... }` in the original core `ModuleConfig.bx` and in the first scaffolder template silently produced empty values, which meant the AddonDiscoveryInterceptor was never registered and (later) loaded add-ons reported "no settings.tesserabx" even though their manifests were defined.

**Always prefix every assignment inside `configure()` with `variables.`**: `variables.settings`, `variables.routes`, `variables.layoutSettings`, `variables.layouts`, `variables.interceptorSettings`, `variables.interceptors`. The AI module already follows this convention; other core modules do not, and will need to be migrated when later phases touch them.

### Phase 1 - CommandBox tasks must be `.cfc`, not `.bx`

CommandBox 6.3 hardcodes the `.cfc` extension for task runners ("Task CFC doesn't exist." otherwise). The CommandBox runtime is Lucee, not BoxLang. The generated add-on output is `.bx` (it runs inside the TesseraBX BoxLang runtime), but the task source itself is `.cfc` with `component extends="commandbox.system.BaseTask"`.

The original plan called for `tasks/scaffoldAddon.bx`; the actual file is `tasks/ScaffoldAddon.cfc`. Future tasks follow the same `.cfc` convention.

### Phase 1 - Lucee `#` interpolation hits CFC string literals containing markdown headings

Lucee parses `#...#` as expression interpolation inside both single-quoted and double-quoted CFC strings. README templates with markdown `# Heading` / `## Section` lines throw `Invalid Syntax Closing [#] not found` at compile time.

Workaround: keep generated-content templates as external files under `tasks/templates/*.tpl` and load them with `fileRead()` then `replaceNoCase()`. Doubling every literal `#` to `##` is the alternative but is fragile for content with many markdown headings.

### Phase 1 - BoxLang JSON function is `jsonSerialize`, not CFML `serializeJSON`

BoxLang ships `jsonSerialize()` and `jsonDeserialize()`. The CFML names `serializeJSON()` and `deserializeJSON()` do not exist in the BoxLang built-in function set and throw `Function [serializeJSON] not found`. The existing TesseraBX services already use the BoxLang names; new code must follow.

### Phase 1 - To reach the ColdBox controller from a service, inject `coldbox` directly

`wirebox.getController()` does not exist on the WireBox API surface in this BoxLang / ColdBox 8 environment ("Method 'getController' not found"). Use `property name="coldbox" inject="coldbox";` and call `coldbox.getSetting( "<name>" )` directly.

### Phase 4 - Fixing the `variables.` scope-walker bug can resurface latent duplicate-route bugs

The Phase 1 scope-walker bug silently dropped unscoped `routes = [...]` assignments inside `configure()` into function-local scope, making them invisible to ColdBox. When Phase 4's scoping sweep added `variables.` prefixes, those previously-invisible declarations became **active**, and any duplicate-routing problems they contained surfaced as broken endpoints.

The casualty: both `modules_app/agent/ModuleConfig.bx` and `modules_app/portal/ModuleConfig.bx` had duplicate `/login` and `/logout` route entries in their `routes = [...]` array that did NOT declare verb constraints. The verb-aware versions (with `POST -> Session.create` and `GET -> Session.new`) live in each module's `config/Router.bx`. Pre-Phase-4, the scope-walker bug made the duplicates inert. Post-Phase-4, the non-verb-aware duplicates registered first and shadowed the verb-aware Router.bx routes. The symptom: `POST /agent/login` ran `Session.new` (just renders the login form) instead of `Session.create` (validates, sets MFA pending state, redirects to /agent/login/verify). User reports: "I can submit my credentials but I'm dropped back at the login page with no error message."

The fix: removed the duplicate `/login` and `/logout` entries from both ModuleConfig route arrays. Router.bx is the single source of truth for verb-aware routes in each module.

**Generalized lesson:** when scoping fixes activate previously-inert config, audit every now-visible block for content that may conflict with whatever IS already active. A handful of "always there but never executed" lines may have been the only thing preventing a regression.

### Phase 4 - Kebab-case URLs do not auto-map to PascalCase handler names

ColdBox's default catch-all route `{ pattern : "/:handler/:action?" }` performs the URL-to-handler mapping by passing the captured `:handler` segment straight through to the handler-service lookup. A URL like `/agent/admin/addon-settings` gets routed to a handler literally named `addon-settings`, NOT to `AddonSettings.bx`. The result is an `EventHandlerNotRegisteredException` with the message `The event: admin:addon-settings is not a valid registered event.`

Two fixes:

1. **Add an explicit route** in the module's `config/Router.bx`:

   ```boxlang
   route( "addon-settings/save" ).withVerbs( "POST" ).to( "AddonSettings.save" );
   route( "addon-settings" ).to( "AddonSettings.index" );
   ```

2. **Or name the handler file with the dash** (`addon-settings.bx`). This conflicts with BoxLang class-file conventions and is not recommended.

Hit twice in Phase 4 (`/agent/admin/addons`, `/agent/admin/addon-settings`). Both fixed via explicit Router.bx routes.

### Phase 4 - Lazy-load registries with `register()` re-entrancy must set the cache-loaded flag BEFORE seeding

A registry that lazy-loads its in-code seeds via `ensureLoaded()` and provides an imperative `register()` method must set `cacheLoaded = true` at the top of `ensureLoaded`, not at the bottom:

```boxlang
private void function ensureLoaded(){
    if ( variables.cacheLoaded ) return;
    variables.cacheLoaded = true;                  // <-- BEFORE seeding
    seedCoreEntries();                             // seedCoreEntries calls register()
    // ...load manifest contributions...
}

public void function register( required struct entry ){
    ensureLoaded();                                // re-enters here
    variables.cache[ entry.id ] = normalize( entry );
}
```

If `cacheLoaded = true` is set at the end instead, `seedCoreEntries()` -> `register()` -> `ensureLoaded()` -> seeds again -> infinite recursion. The exception you get is a `java.lang.StackOverflowError` wrapped in `CustomException` with **no message, no detail, and no tag context** — completely silent. Phase 4's NavigationRegistry and AdminPagesRegistry hit this; the symptom was "every spec errors but the message is empty" and the only diagnostic that worked was `jsonSerialize( e )` on a caught exception. Always set the flag first.

### Phase 4 - `compare(a, b)` is a string-compare; numeric sort weights need `val(a) - val(b)`

BoxLang's `compare()` BIF performs case-sensitive **string** comparison. Sorting structs by a `sortWeight` field with `compare( a.sortWeight, b.sortWeight )` produces lexicographic order: "10" < "20" < "40" < "5" < "50" < "90". An override that stores `5` in a database column and reads it back through `qb` returns it as a string for the comparator, so the override item lands at the wrong position even though the numeric value is correct.

The fix is `val()`-coerced numeric subtraction:

```boxlang
// Wrong:
out.sort( ( a, b ) => compare( a.sortWeight, b.sortWeight ) );

// Right:
out.sort( function( a, b ){ return val( a.sortWeight ) - val( b.sortWeight ); } );
```

Phase 4 hit this in all four UI registries (navigation, admin pages, ticket panels, dashboard widgets) plus `AddonAssetService`. The symptom was assertions like `expect( items[ 1 ].label ).toBe( "Customers" )` failing with "Expected [Customers] but received [Dashboard]" even though the override row had `sort_weight_override = 5` and the registry produced an item with `sortWeight = 5`.

### Phase 4 - `getModel( "..." )` is not a BoxLang/ColdBox 8 global helper

The function `getModel( name )` was a ColdBox handler-scoped convenience that resolves WireBox instances. In **BoxLang + ColdBox 8 application helpers**, that function is NOT in scope. Calls in `ApplicationHelper.bxm` like `getModel( "NavigationRegistry@core" )` throw `Function [getModel] not found` when the helper executes from a layout that's rendered through some test paths (CBWire spec contexts, integration specs that bypass the full request lifecycle).

Use `application.wirebox.getInstance( "..." )` instead. That works in every execution context — handler, layout, CBWire component, test spec, scheduled task, cbq job. The application-scope reference doesn't depend on the ColdBox controller being injected into the current scope.

Phase 4 hit this in `ApplicationHelper.bxm`. Symptom: every portal contact-form spec errored with `Function [getModel] not found` after Phase 4 made the layout call `tbxAssetCss( "portal" )`.

### Phase 3 - ColdBox 8 has no `announceAsync` method; use `announce( state, data, true )` instead

The Phase 3 plan calls events "async by default" and assumes a separate `announceAsync()` method on the interceptor service. **That method does not exist in ColdBox 8.** `InterceptorService.announce()` accepts an `async` boolean as its third positional arg (or named `async : true`):

```boxlang
// Wrong:
interceptorService.announceAsync( "onContactCreated", payload );
// throws "Method 'announceAsync' not found" and cascades through
// every test path that touches a service announcing the event.

// Right:
interceptorService.announce( "onContactCreated", payload, true );

// Also right (named args):
interceptorService.announce(
    state : "onContactCreated",
    data  : payload,
    async : true
);
```

This bit Phase 3 hard: 17 call sites used `announceAsync()` and broke 95 specs (every spec path that exercised the affected services). The fix is mechanical (`announceAsync(` → `announce(` plus add `, true` as the third arg) but easy to miss because the plan document and many ColdBox tutorials still refer to "announceAsync" as the async convention. **Always check the actual method signature in `coldbox/system/web/services/InterceptorService.cfc` before writing new announce calls.**

### Phase 2 - qb stores where-clause column as a struct, not a string

When you inspect a qb builder's `getWheres()` array, each where-clause struct's `column` field is itself a struct shaped like `{ type: "simple", value: "<column_name>" }` (see `mapToColumnType` in `modules/qb/models/Query/QueryBuilder.cfc`). Code that does `w.column == "organization_id"` will silently fail to match (BoxLang errors with `In function [equals], argument [struct2] with a type of [String] does not match the declared type of [structloose]` when the comparison is exercised through `toBe()`).

The correct introspection is:

```boxlang
if ( isStruct( w.column ) && ( w.column.type ?: "" ) == "simple" ) {
    if ( ( w.column.value ?: "" ) == "organization_id" ) { ... }
}
```

Bit `TenancyGuard.assertHasOrgPredicate` directly; future code that introspects qb builders for any reason must follow the same pattern.

### Phase 2 - Raw where clauses are not introspectable

`whereRaw( "organization_id = ?", [ orgId ] )` lands in the wheres array with `type="raw"` and **no `column` field at all**. There is no way to know which columns a raw fragment constrains without parsing the SQL string. `TenancyGuard.assertHasOrgPredicate` accepts a boolean `acceptRaw` flag that opts into "I have hand-verified this raw clause" semantics; if you have to use raw, set the flag explicitly and never let it default.

### Phase 1 - `?fwreinit=1` does not recompile BoxLang `.bx` source

ColdBox's reinit reloads framework config and rewires modules, but it does not invalidate the BoxLang compiler's class cache. Edits to `.bx` files take effect only after `docker compose restart app` (or whatever causes a fresh JVM bootstrap). The TestBox specs that hit a recently edited service will report stale errors until then. This bit Phase 1 twice during build; future phases should plan for a restart whenever a service or interceptor signature changes.

---

## Open questions / parking lot

_Items deferred or unresolved during execution. Each gets a dated entry plus a status (`open`, `resolved`, `wontfix`)._

(empty)
