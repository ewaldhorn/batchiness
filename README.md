# Batchiness

A small, self-contained [Odin](https://odin-lang.org/) library for driving a real browser
`CanvasRenderingContext2D` in **batched** mode from WebAssembly.

Instead of calling the Canvas 2D API one method at a time across the WASM↔JS boundary — one
bridge crossing per `fillRect` / `arc` / `fill`, which is expensive at 60fps — you record a whole
frame's worth of draw operations into one packed byte buffer in Odin, then flush it to the
browser with a **single** foreign call. The JS side walks the buffer and replays each op onto the
context.

This library was extracted from [OdinDOM](../odindom)'s `canvas_cmd` package to stand alone: it
contains *only* the batched canvas draw operations plus the minimal bootstrap needed to create a
canvas and run an animation loop. No general DOM manipulation, no Web Audio, no pixel buffers.

## Layout

| Path | What it is |
|------|-----------|
| `batch/batch.odin` | The command buffer + every draw op (rects, paths, arcs, text, transforms, gradients, shadows, sprites). |
| `batch/canvas.odin` | Tiny bootstrap: `Handle` type, `get_element_by_id`, `canvas_create`, `canvas_get_context`, `start_animation_loop`, `add_event_listener`. |
| `web/batchiness.js` | The JS glue: Odin's `js_wasm32` runtime hooks (`odin_env`) plus the `batch_env` bridge that replays the command buffer. |
| `docs/` | A runnable example app (a tree + a swimming duck) — build target for GitHub Pages. |

## Build & run

Requires the [Odin compiler](https://odin-lang.org/docs/install/) and Node (for `http-server`).

```sh
./run.sh        # builds the docs example, serves on http://localhost:9000
./build.sh      # rebuild the docs WASM only (no server)
```

Then open <http://localhost:9000/docs/index.html>.

> **Never open the HTML via `file://`** — the page fetches its `.wasm` over HTTP, and the browser
> blocks that with a CORS error. Always serve over HTTP (`./run.sh`).

Build flags (library mode, driven by JS-called exports rather than `main()`):
`-target:js_wasm32 -o:size -no-entry-point`.

## Using it

Your app is a `package main` that imports `batch` and exports two `"c"`-convention procs the JS
loader calls:

- `batchiness_main :: proc "c" ()` — runs once after instantiation.
- `batchiness_invoke_callback :: proc "c" (id: u32)` — dispatched for every animation frame and
  registered DOM event, keyed by an app-chosen `id`.

`context = runtime.default_context()` must be the first line of **every** exported `"c"` proc — it
re-establishes Odin's runtime state at each JS→Odin boundary crossing.

```odin
package main

import "base:runtime"
import "../batch"

ctx: batch.Handle
cmd: batch.Buffer

@(export)
batchiness_main :: proc "c" () {
	context = runtime.default_context()
	canvas := batch.canvas_create(batch.get_element_by_id("app"), 480, 300)
	ctx = batch.canvas_get_context(canvas)
	batch.start_animation_loop(0) // callback id 0 fires once per frame
}

@(export)
batchiness_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	batch.reset(&cmd)                       // rewind the buffer
	batch.set_fill(&cmd, "#3f8fc4")
	batch.fill_rect(&cmd, 20, 20, 200, 120) // record ops...
	batch.flush(ctx, &cmd)                  // ...and replay them in one crossing
}
```

Load it from a page:

```html
<div id="app"></div>
<script src="./batchiness.js"></script>
<script>Batchiness.instantiate("example.wasm");</script>
```

## The command buffer

`batch.Buffer` is a fixed-capacity (1 MiB) preallocated arena, reused every frame — no per-frame
heap churn. The lifecycle is always:

1. `batch.reset(&cmd)` at the start of the frame.
2. Record draw ops (`fill_rect`, `begin_path`/`arc`/`fill`, `linear_gradient`, `draw_sprite`, …).
3. `batch.flush(ctx, &cmd)` — one foreign call replays the whole frame.

### Sprites

Detailed artwork (a tree, a character) can be **baked once** into an offscreen canvas, then blitted
cheaply every frame instead of re-encoding its paths:

```odin
// once:
batch.bake_begin(&cmd, sprite_id, w, h)
// ... draw the art ...
batch.bake_end(&cmd)
// each frame:
batch.draw_sprite(&cmd, sprite_id, x, y)
```

### What's covered

State (fill/stroke/line width/font/alpha/line cap), rectangles, paths (move/line/arc/ellipse/bezier/
rect/fill/stroke/clip), text (`fill_text`/`stroke_text` + synchronous `measure_text`), transforms
(translate/scale/rotate/set_transform), linear & radial gradients, shadows, and sprites. See
`batch/batch.odin` for the full op list; the wire format is documented at the top of that file and
must stay in sync with the `switch` in `web/batchiness.js`.

## Licence

MIT — see [LICENSE](LICENSE).
