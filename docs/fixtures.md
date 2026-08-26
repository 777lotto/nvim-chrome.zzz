# Deterministic Chrome fixtures

Fixtures are callback-free schema-v1 catalog data returned defensively by
`require("ux_chrome").fixtures()`. Each component publishes stable scenario,
highlight-property, structural-property, layout, and rollback metadata.
Executable render functions stay outside the manifest. Screenshots may aid
manual review but are not regression oracles.

## Common editor sizes

All component catalogs declare 24 lines and these preview widths:

| Layout | Columns |
| --- | ---: |
| Wide | 100 |
| Medium | 72 |
| Narrow | 40 |

The separate renderer suite compares deterministic text, display width, and
stable state identity across wide, medium, narrow, and pathological bounds. The
Styling integration additionally verifies real `UXChrome*` spans and property
IDs in its generic manifest preview.

## Buffer tabs

The exported buffer catalog contains stable active, inactive, selected,
modified, and overflow rows. The renderer regression matrix additionally uses:

- an active modified buffer;
- visible modified and visible unmodified buffers;
- inactive and inactive-modified buffers;
- enough entries to exercise overflow markers;
- active and inactive native tab pages; and
- the stable empty-buffer-list state.

The structural catalog declares `slant`, `slope`, `thin`, `block`, and custom
separator models. The
declared slant is ``/``; modification is `●`; overflow uses ``/``.

## Statusline

The statusline catalog maps representative rows to managed properties. Renderer
tests cover normal, insert, visual, replace, command, terminal, and inactive
states. Wide output includes filename, modified/read-only markers, encoding,
file format, filetype, progress, and ruler. Narrow output drops lower-priority
metadata and truncates safely.

The declared section separators are `` and ``; the component separator is
`│`. Mode accents follow the current Macchiato behavior: blue, green, mauve,
red, peach, and green respectively.

## Winbar, gutter, and folds

Renderer cases include unnamed, shallow, deep, modified, active, inactive, and
narrow breadcrumbs. The separator is ` › ` and the declared maximum depth is
four.

Statuscolumn cases include absolute current-line numbering, relative surrounding
lines, disabled numbers, virtual lines, signs, open/closed/continuing folds, and
the gutter separator. Fold text covers empty text, whitespace normalization,
multibyte input, exact line counts, and truncation.

## Windows and scrollbar

Window fixtures cover active/inactive treatment, inherited versus dim inactive
style, split glyphs, an externally owned `winhighlight`, newly opened windows,
and a window that closes before restoration.

Scrollbar tests cover proportional geometry, cached redraw, a real 120-line
Neovim viewport, marker placement, disable, and teardown. Production render
modules contain no
filesystem, subprocess, Git, network, language-server, or other domain access.

## Transaction and lifecycle cases

The local and cross-repository test suites prove:

- Foundation-only startup with Styling absent;
- a distinct `ux.chrome` Styling category and preview;
- coexistence with M2 Bufferline and Lualine adapter registrations;
- no-profile output equal to declared defaults;
- ColorScheme replay and late registration;
- exact undo, redo, reset, revert, and close-without-save behavior;
- apply and rerender failure rollback;
- repeated setup/refresh/teardown without duplicate commands or autocmds; and
- `external` ownership performs no writes while explicit teardown restores all
  acquired global and window-local state.
