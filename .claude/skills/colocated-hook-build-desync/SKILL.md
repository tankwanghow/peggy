---
name: colocated-hook-build-desync
description: Use when the esbuild/asset build fails with `Could not resolve "./PeggyWeb.<Module>/<n>_<hash>.js"` (in `_build/dev/phoenix-colocated/peggy/index.js`), or after editing a module that defines a `<script :type={Phoenix.LiveView.ColocatedHook}>` and the JS watcher then breaks. Explains why and the one-command fix.
---

# Colocated-hook build desync

## Symptom

The dev asset build (esbuild, e.g. under `iex -S mix phx.server` or
`mix assets.build`) fails with:

```
✘ [ERROR] Could not resolve "./PeggyWeb.CoreComponents/782_y4m…la.js"
    ../_build/dev/phoenix-colocated/peggy/index.js:3:42
```

The Phoenix server itself is fine — only the JS asset bundler errors.

## Root cause

Phoenix LiveView extracts each `<script :type={Phoenix.LiveView.ColocatedHook}>`
(and `ColocatedJS`) into a file under
`_build/dev/phoenix-colocated/peggy/<DefiningModule>/`, named by the **line
number** where the `<script>` tag sits, e.g. `742_<contenthash>.js`. The
generated `index.js` imports those files by exact filename.

So the filename depends on the hook's **line position**. If you insert or
delete lines *above* a colocated hook (e.g. add a function/component earlier
in `core_components.ex`), the hook moves to a new line → its extracted file is
renamed (`711_…` → `742_…`). A build that catches this mid-shift can leave
`index.js` importing the old filename while the directory holds the new one
(or the subdir ends up empty), and esbuild can't resolve the import.

Modules in this repo that define colocated hooks and are prone to this:
`core_components.ex` (`.IframePrint`, `.InfiniteScroll`), the `*Print`
LiveViews (`.AutoPrint`), `mobile/animal_detail.ex` & `farm/animal_detail.ex`
(`.HistoryBack`), `data_import.ex` (`.DownloadFailures`).

## Fix

Force a clean re-extraction so `index.js` and the per-hook files regenerate
together:

```bash
rm -rf _build/dev/phoenix-colocated/peggy && mix compile --force
```

Then confirm esbuild resolves: `mix assets.build` (should end with the
`app.js` size line, no `Could not resolve`). The running `phx.server` watcher
recovers on its next build cycle.

## Verify it really desynced (optional)

```bash
# files present in the module's colocated dir …
ls _build/dev/phoenix-colocated/peggy/PeggyWeb.CoreComponents/
# … vs what index.js imports — the <n>_ prefixes must match.
grep "PeggyWeb.CoreComponents/" _build/dev/phoenix-colocated/peggy/index.js
```

A mismatch (or an empty dir with non-empty imports) confirms the desync.

## Avoiding it

The content hash is unchanged when you only move a hook, so this is cosmetic —
not a code bug. Just know that **editing above a colocated hook can break the
asset build until a `mix compile --force`**. It is not caused by the edit being
wrong.
