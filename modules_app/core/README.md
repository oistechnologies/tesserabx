# core

Responsibility, owned entities, public service interface, and events for the `core` module.

See [CLAUDE.md](../../CLAUDE.md) for hard constraints and [docs/BUILD-PLAN.md](../../docs/BUILD-PLAN.md) for the phased build order.

## Owned entities

To be populated as the module is built.

## Public service interface

To be populated as the module is built.

## Events emitted

To be populated as the module is built.

## Shared view partials

`core/views/_partials/` exposes reusable view fragments that both surfaces and add-ons can include via `#view( view = "_partials/<name>", module = "core", args = {...} )#`:

- `layout_head.bxm` — `<head>` block: vendor stylesheets self-hosted under `/includes/vendor/`, theme pre-paint script, brand color override, add-on CSS hook. Required arg: `surface` ("agent" or "portal").
- `layout_scripts.bxm` — end-of-body block: vendor JS, OverlayScrollbars sidebar init, highlight.js + CFML aliases, theme-toggle wire-up, attachment dropzone, add-on JS hook. Required arg: `surface`.
- `theme_toggle.bxm` — light/dark/auto color-mode dropdown for the navbar. Reads/writes `localStorage['tbx-theme']`. No args.
- `small_box.bxm` — AdminLTE 4 `.small-box` KPI tile. Required args: `color`, `metric`, `label`, `icon`. Optional: `caption`, `link`, `linkLabel`. Documented in [docs/EXTENSIONS.md#reusable-small-box-partial](../../docs/EXTENSIONS.md).
- `avatar.bxm` — small agent avatar that falls back to initials. Args: `agent`, `size`.
- `attachment_dropzone.bxm` — progressively-enhances every `<input type="file" multiple>` with a drag/drop chip preview. No args.
