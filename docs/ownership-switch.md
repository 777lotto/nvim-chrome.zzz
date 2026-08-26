# Chrome ownership switch

UX Chrome separates behavioral surface ownership from schema-v1 presentation
values. A profile can change separators, glyphs, colors, and layout values; it
cannot silently displace another plugin from `tabline`, `statusline`, `winbar`,
`statuscolumn`, window treatment, or scrollbar ownership.

## Ownership modes

- `auto` acquires an available native surface but preserves a detected external
  expression or owner.
- `ux` is an explicit instruction for UX Chrome to snapshot and own the surface.
- `external` keeps the surface untouched while the `ux.chrome` manifest and
  fixtures remain available to Foundation and Styling.
- `takeover` normalizes to `ux`; `off` normalizes to `external`.

The canonical serialized/debug values are always `auto`, `ux`, or `external`.

## M3 coexistence

The current configuration continues to use Bufferline for the tabline and
Lualine for the statusline. M3 does not migrate the live configuration or edit
its protected lockfile.

For isolated dogfood, retain those physical owners explicitly:

```lua
require("ux_chrome").setup({
  ownership = {
    tabline = "external",
    statusline = "external",
    winbar = "auto",
    statuscolumn = "auto",
    windows = "auto",
    scrollbar = "auto",
  },
})
```

Chrome registers `ux.chrome`, claims only `UXChrome*` highlights and
component-scoped keys through the `ux_chrome` adapter, and does not rewrite
`BufferLine*`, `lualine_*`,
or their M2 adapter registrations. Loading Styling is optional and must not
initialize a renderer or perform domain I/O.

Use explicit `external`, rather than depending on plugin load order, for every
surface already assigned to another plugin.

## M4 forward switch

Perform one surface at a time after deterministic parity and rollback tests
pass:

1. Record the current plugin specification, mappings, setup input, native
   option values, and relevant saved profile overrides.
2. In UX Styling configuration, disable the corresponding M2 compatibility
   adapter (`bufferline` or `lualine`) so its category no longer represents the
   active implementation.
3. Disable the third-party renderer for that surface. Do not delete its lockfile
   entry until rollback acceptance is complete.
4. Map accepted saved adapter properties to the stable `ux.chrome` property IDs;
   do not silently reinterpret incompatible values.
5. Set the Chrome surface ownership to `ux`, then call `refresh()`.
6. Verify wide, medium, narrow, active/inactive, modified, overflow, failure,
   restart, and ColorScheme cases in an isolated configuration.
7. Remove obsolete mappings only after equivalent Chrome commands are proven.

Tabline and statusline are separate switches. Native winbar, statuscolumn,
window treatment, and scrollbar can likewise be promoted independently.

## Rollback

1. Call `require("ux_chrome").disable(surface)` or `teardown()` for the complete
   runtime. Teardown is the exact physical-restoration boundary.
2. Restore ownership to `external` for the affected surface.
3. Re-enable the prior plugin specification and exact setup input.
4. Re-enable its Styling compatibility adapter.
5. Restore the previous mappings and confirm the saved adapter property IDs are
   still preserved.

Do not use `reset()` as a migration rollback. Reset means Chrome's declared
presentation defaults; teardown means restoration of state captured before
Chrome acquired the surface.

## Conflict and failure rules

- `auto` must not overwrite a non-empty external native option expression.
- `external` must produce zero writes to the surface.
- Failed acquisition or refresh restores every mutation before returning an
  error and does not publish a new ownership state.
- Closed windows are skipped safely during restoration; surviving captured
  windows restore their exact local values.
- Chrome never uses private Bufferline/Lualine APIs and never performs Git,
  GitHub, language-server, or network I/O.
