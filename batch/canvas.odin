// Package batch is a self-contained Odin/WASM library for driving a real browser
// CanvasRenderingContext2D in *batched* mode: record a whole frame of Canvas2D draw operations
// into one packed byte buffer, then flush it to the browser with a SINGLE WASM<->JS call.
//
// This file holds the tiny bootstrap needed to get a canvas and a 2D context to draw onto
// (everything else in the package is pure drawing — see batch.odin). It is deliberately minimal:
// batchiness does DOM manipulation, Web Audio, events wholesale, etc. — only what it takes to
// create a canvas and run an animation loop.
package batch

// ------------------------------------------------------------------------------------------------
// Handle references a live JS object (a canvas element or its 2D context) stored in the JS-side
// handle table and addressed by integer id. 0 is null / invalid.
Handle :: distinct u32

INVALID :: Handle(0)

// ------------------------------------------------------------------------------------------------
// Imported JS functions (provided by web/batchiness.js).
// ------------------------------------------------------------------------------------------------

foreign import batch_env "batch_env"

@(default_calling_convention = "contextless")
foreign batch_env {
	batch_get_element_by_id   :: proc(id: string) -> Handle ---
	batch_canvas_create       :: proc(parent: Handle, width, height: u32) -> Handle ---
	batch_canvas_get_context  :: proc(canvas: Handle) -> Handle ---
	batch_start_animation_loop :: proc(cb_id: u32) ---
	batch_add_event_listener  :: proc(elem: Handle, event: string, cb_id: u32) ---
	batch_log                 :: proc(msg: string) ---
	batch_now                 :: proc() -> f64 ---
}

// ------------------------------------------------------------------------------------------------
// is_valid reports whether a handle is non-null.
is_valid :: proc "contextless" (h: Handle) -> bool {
	return h != INVALID
}

// ------------------------------------------------------------------------------------------------
// get_element_by_id returns the element handle matching the given id, or INVALID.
get_element_by_id :: proc "contextless" (id: string) -> Handle {
	return batch_get_element_by_id(id)
}

// ------------------------------------------------------------------------------------------------
// canvas_create creates a <canvas> of the given size and appends it to parent, returning its
// handle.
canvas_create :: proc "contextless" (parent: Handle, width, height: int) -> Handle {
	return batch_canvas_create(parent, u32(width), u32(height))
}

// ------------------------------------------------------------------------------------------------
// canvas_get_context retrieves the "2d" rendering context of a canvas — this is the handle you
// pass to flush().
canvas_get_context :: proc "contextless" (canvas: Handle) -> Handle {
	return batch_canvas_get_context(canvas)
}

// ------------------------------------------------------------------------------------------------
// start_animation_loop drives a requestAnimationFrame loop, invoking the host app's
// batchiness_invoke_callback dispatcher with cb_id on every frame.
start_animation_loop :: proc "contextless" (cb_id: u32) {
	batch_start_animation_loop(cb_id)
}

// ------------------------------------------------------------------------------------------------
// add_event_listener registers a DOM event listener on elem. cb_id identifies the callback to the
// host app's batchiness_invoke_callback dispatcher.
add_event_listener :: proc "contextless" (elem: Handle, event: string, cb_id: u32) {
	batch_add_event_listener(elem, event, cb_id)
}

// ------------------------------------------------------------------------------------------------
// log writes a message to the browser developer console.
log :: proc "contextless" (msg: string) {
	batch_log(msg)
}

// ------------------------------------------------------------------------------------------------
// now returns milliseconds since page load (performance.now()).
now :: proc "contextless" () -> f64 {
	return batch_now()
}
