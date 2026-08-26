# Changelog

All notable changes to this project will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and releases use Semantic Versioning.

## [Unreleased]

### Added

- Initial UX Chrome implementation for buffer tabs, native tab pages,
  statusline, winbar breadcrumbs, statuscolumn and fold presentation, split and
  active-window treatment, and a lightweight scrollbar.
- Direct UX Foundation schema-v1 registration with UX-owned highlight and
  structural identities; UX Styling remains optional.
- Per-surface `auto`, `ux`, and `external` ownership modes, including the
  `takeover` and `off` compatibility aliases.
- Deterministic wide, medium, and narrow fixtures and focused unit, renderer,
  smoke, Foundation-integration, and Styling-integration suites.
- Public Lua APIs, user commands, health/debug reporting, Vim help, and M3/M4
  ownership-switch documentation.

### Fixed

- The Styling discovery test asserted that a whole-plugin generic preview
  borrowed the first component's `fixture_id`. UX Styling no longer does that,
  so the assertion now expects the plugin-derived `ux.chrome.preview.v1`.

- The statuscolumn expression embedded its callback as `%{...}`, so the
  highlight prefix the callback returns was printed into the gutter as literal
  text and the column rendered far wider than its cells. It now uses `%{%...%}`,
  which Neovim re-parses as statusline syntax.
- Ownership reconciliation no longer runs on high-frequency editing events.
  `CursorMoved`, `CursorMovedI`, `ModeChanged`, `TextChanged*` and `WinScrolled`
  previously scheduled a full reconcile of every surface in every window, which
  cost roughly 2.8 ms of work per keystroke; they now take a cheap redraw path.
- `OptionSet` raised by Chrome's own option writes is ignored during a
  reconcile, which previously caused every reconcile to schedule a second one.
- `fillchars` and `winhighlight` entries that Chrome adds are appended in sorted
  order. They were previously emitted in `pairs()` order and so differed between
  processes.
