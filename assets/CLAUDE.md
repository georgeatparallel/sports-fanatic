Parent: `../CLAUDE.md`

# CLAUDE.md — Frontend assets

> See the Documentation Placement Rule in `../CLAUDE.md` before adding
> content here.

---

Tailwind 3, esbuild, vanilla JS for LiveView hooks.

## Layout

```
assets/
  css/app.css           Tailwind entry, custom layer overrides
  js/app.js             LiveView socket + hooks
  vendor/               Third-party JS shipped without npm
  tailwind.config.js    Tailwind config
```

## Commands

```bash
mix assets.setup     # install tailwind + esbuild binaries
mix assets.build     # compile (development)
mix assets.deploy    # minified production build + phx.digest
```

Esbuild + Tailwind versions are pinned in `config/config.exs`:

- `esbuild ~> 0.17.11`
- `tailwind ~> 3.3.2`

## LiveView JS hooks

Hooks live in `assets/js/app.js` under the `Hooks` object passed to the
`LiveSocket` constructor.

| Hook | Used by | Purpose |
|------|---------|---------|
| `ScrollBottom` | ChatLive / NewsLive chat mode | Auto-scroll the chat container on new messages (CHAT-002) |

When adding a hook:

1. Add to the `Hooks = { ... }` literal in `app.js`.
2. Reference from the template via `phx-hook="MyHook"`.
3. If the hook reads `data-*` attributes, document them inline in `app.js`.
4. If the hook depends on a Phoenix event, ensure a matching
   `handle_event/3` clause exists in the LiveView.

## Static assets

Static files go under `priv/static/`. The OG image fallback for the injury
report lives at `priv/static/og/injury-default.png` (see
`lib/sports_fanatic/x/CLAUDE.md`).

Per-player OG photos go to `priv/static/og/players/{sanitized_slug}.png`
where `sanitized_slug` is produced by `SportsFanatic.Storage.sanitize_key/1`.
