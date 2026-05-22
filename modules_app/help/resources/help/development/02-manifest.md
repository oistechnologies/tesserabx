## Manifest fields

| Field            | Required | Notes                                                                                          |
| ---------------- | -------- | ---------------------------------------------------------------------------------------------- |
| `addonId`        | yes      | Stable slug. Becomes the primary key in the `addons` table. Use kebab-case.                    |
| `displayName`    | yes      | Human-readable label shown in the admin Add-ons page.                                          |
| `version`        | yes      | Your add-on's own version. Used for display only; TesseraBX does not compare add-on versions. |
| `minCoreVersion` | yes      | Minimum TesseraBX core version your add-on supports. Add-on is rejected if core is older.      |
| `maxCoreVersion` | no       | Inclusive maximum. **Blank, missing, or omitted means "any version >= minCoreVersion"**.        |
| `contributesTo`  | no       | Array of contribution kinds for documentation purposes. No runtime enforcement.                |
| `requiresAi`     | no       | Defaults to false. When true, every UI surface this add-on contributes is hidden when `AI_ENABLED=false` (enforced once Phase 4's UI registries land).  |

### Version-range semantics

`minCoreVersion` is required. `maxCoreVersion` is optional with intentional "open upper bound" semantics:

- When `maxCoreVersion` is blank, missing, or the key is omitted entirely, the add-on is accepted on **any core version equal to or greater than `minCoreVersion`**. An add-on author can opt into "works forever forward" without having to bump the manifest on every TesseraBX release.
- When `maxCoreVersion` is present, it caps the supported range inclusively.

Versions are compared in semantic-version style ("1.10.0" > "1.2.0"). Pre-release suffixes after a dash are ignored.

If the running TesseraBX version falls outside an add-on's declared range, the add-on is still recorded in the `addons` table but marked `compatible = false` with a `compatibility_message`. The admin UI will surface the incompatibility, and `AddonRegistryService.isEnabled()` returns false for the add-on at every tenant.

The running TesseraBX version is read from the `appVersion` setting in `config/Coldbox.bx`. Bump that and the matching value in `box.json` together on every release.

---

## Discovery

At app boot, the `AddonDiscoveryInterceptor` listens on ColdBox's `afterAspectsLoad` event. Once every module has been loaded, the interceptor calls `AddonRegistryService.syncFromLoadedModules()`, which:

1. Walks `controller.getSetting( "modules" )` to find every loaded ColdBox module.
2. Skips modules without a `settings.tesserabx` block.
3. Validates each manifest has the required fields. A missing required field is logged and the module is skipped.
4. Compares each manifest's `minCoreVersion` and `maxCoreVersion` against the running `appVersion`.
5. Upserts a row into `addons`, preserving any existing `enabled` and `enablement_mode` choices an admin previously made.

The sync runs on every app boot, so reinstalling, reinit'ing, or restarting picks up new manifests and notices changes to existing ones.

A row in `addons` represents a **discovered** add-on, not necessarily an **enabled** one. See enablement below.

---

