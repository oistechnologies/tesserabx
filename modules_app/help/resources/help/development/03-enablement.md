## Enablement resolution

Add-ons can be globally enabled or disabled, and within that, can be set to apply to every organization or only to a chosen subset.

The data model:

- `addons.enabled` (boolean): the global on/off switch for the add-on. Defaults true when first discovered.
- `addons.enablement_mode` (string, `'all'` or `'specific'`): when the add-on is globally enabled, this picks the resolution rule.
- `addon_organization_enablement` (table): per-organization rows used only when `enablement_mode = 'specific'`.

Call `AddonRegistryService.isEnabled( addonId, organizationId )` from any code that needs to know whether to honor an add-on's contribution at a specific tenant. The resolution rule is:

```
addons.enabled = false                           ⇒ false   (off everywhere)
add-on marked incompatible at discovery          ⇒ false   (off everywhere)
enablement_mode = 'all'                          ⇒ true    (on for every organization)
enablement_mode = 'specific' AND row exists      ⇒ that row's enabled value
enablement_mode = 'specific' AND no row exists   ⇒ false   (default off in specific mode)
```

A deployment that does not want per-tenant granularity simply leaves every add-on in `enablement_mode = 'all'`. The admin UI lands in Phase 4; until then, switching modes or setting per-org rows is done through `AddonRegistryService.setEnablementMode()` and `setOrgEnablement()` or direct SQL.

---

## Scaffolding a new add-on

A CommandBox task generates a skeleton TesseraBX add-on under `modules/<slug>/` with the manifest block pre-filled, the standard folder layout, a placeholder install spec, and a README:

```bash
box task run tasks/ScaffoldAddon.bx <addon-slug> [displayName="Friendly Name"]
```

The generated module is a valid ColdBox module that loads cleanly and registers in the `addons` table on the next reinit. Open `modules/<slug>/ModuleConfig.bx`, edit the manifest details, then start adding handlers, services, and (as registries land in later phases) contributions to those registries.

---

