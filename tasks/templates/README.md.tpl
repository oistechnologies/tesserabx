# {{LABEL}}

A TesseraBX add-on.

## Installation

```
box install {{SLUG}}
```

The module will be discovered at the next app boot. Check the admin Add-ons page (or the `addons` database table) to confirm it registered.

## What this skeleton gives you

- A pre-filled `ModuleConfig.bx` with the TesseraBX manifest block.
- The standard ColdBox module folder layout (`handlers/`, `models/`, `views/`, `wires/`, `migrations/`, `resources/`, `tests/`).
- A passing `tests/specs/InstallSpec.bx` that asserts the manifest is well-formed.

## Next steps

1. Edit `ModuleConfig.bx`:
   - Fill in `this.author` and `this.webURL`.
   - Bump `version` as you ship.
   - Decide on `minCoreVersion` / `maxCoreVersion`. Leave `maxCoreVersion` blank for an open upper bound.
   - List the registries you will contribute to in `contributesTo` (for documentation; no runtime check).
2. Contribute to whichever TesseraBX registries the phase has shipped. See `docs/EXTENSIONS.md` in the TesseraBX repo for the per-registry contract.
3. Write specs under `tests/specs/`.

## Contract

This add-on follows the TesseraBX extension contract documented at:

- `docs/EXTENSIONS.md` (the live contract)
- `docs/EXTENSIBILITY-PLAN.md` (the phased plan, including which registries are shipped today)
