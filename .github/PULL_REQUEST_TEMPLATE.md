## What changed

<!-- Describe the Chrome presentation problem and resulting behavior. -->

## Scope

- Surface: <!-- tabline / statusline / winbar / statuscolumn / windows / scrollbar / docs -->
- Ownership impact: <!-- none / auto / explicit switch / rollback -->
- Contract impact: <!-- none / schema-v1 compatible / migration required -->

## Validation

- [ ] I targeted the default `bluff` branch.
- [ ] Commit provenance is explicit (human commits signed; brokered agent commits use the expected unsigned identity).
- [ ] Lua compilation and all applicable named test suites pass on Neovim 0.12.2.
- [ ] Foundation and Styling integration pass when affected.
- [ ] No test loaded or mutated the live Neovim configuration.
- [ ] UI changes include deterministic rendered-line/highlight-span evidence.
- [ ] Takeover and failure cases restore exact physical state.
- [ ] README, Vim help, and changelog match user-visible behavior.
