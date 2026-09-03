# Security policy

## Supported versions

Security fixes are applied to the current `bluff` branch and latest release.

## Reporting a vulnerability

Use the repository Security tab to report unsafe option restoration, statusline
expression injection, malformed profile handling, or arbitrary code execution
privately. Do not open a public issue for suspected credential exposure.

Include the affected commit, a minimal configuration, the surface involved,
expected impact, and any suggested mitigation. You should receive an initial
response within seven days.

## Trust boundary

UX Chrome performs presentation work only. It does not run Git commands, make
GitHub or network requests, start language servers, or perform domain I/O.
Rendered buffer names and paths are escaped before entering statusline syntax.

UX Foundation profiles are non-executable JSON. Chrome's Foundation adapter
must snapshot and restore every previewable structural mutation. A surface that
cannot be restored exactly must remain externally owned or unavailable rather
than offering a false live preview.
