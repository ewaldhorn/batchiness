// Batchiness example: batched Canvas2D basics — one tree, one duck, no interaction.
//
// Driving the browser's Canvas 2D API one method call at a time (fillRect, arc, fill, ...) would
// mean one WASM<->JS crossing per call, which gets expensive at 60fps. Batchiness solves that:
// you record a whole frame's worth of Canvas2D commands into one packed byte buffer, then flush
// it to the browser with a SINGLE foreign call. The JS side just walks the buffer and replays
// each command onto a real CanvasRenderingContext2D.
//
// This example draws the smallest interesting animated scene with it: a static tree and a duck
// that swims back and forth, bobbing on the water — sky/pond gradients, offscreen-baked sprites,
// all batched into one bridge crossing per frame.
package main

import "base:runtime"
import "core:math"
import "../batch"

// ------------------------------------------------------------------------------------------------
// Scene layout
// ------------------------------------------------------------------------------------------------
CANVAS_W :: 480
CANVAS_H :: 300
HORIZON_Y :: 190 // sky/ground split

POND_CX :: 240
POND_CY :: 220
POND_RX :: 170
POND_RY :: 45

TREE_X :: 110
TREE_W :: 70
TREE_H :: 110

DUCK_W :: 48
DUCK_H :: 36
DUCK_MIN_X :: POND_CX - POND_RX + 60
DUCK_MAX_X :: POND_CX + POND_RX - 60

// Sprite ids we choose for the offscreen bakes below — batch just treats these as small integer
// keys into a JS-side Map, so any distinct values work.
SPRITE_TREE :: 0
SPRITE_DUCK :: 1

// The only callback this example needs: one animation tick per frame (see start_animation_loop
// below). A real app would add more IDs here for clicks, buttons, etc.
CB_ANIMATION_TICK :: 0

// ------------------------------------------------------------------------------------------------
// State
// ------------------------------------------------------------------------------------------------

// The 2D rendering context batch flushes commands onto.
ctx: batch.Handle

// A reusable command buffer. reset() at the start of every frame, flush() at the end — no
// per-frame allocation.
cmd: batch.Buffer

time: f32 // seconds since start, drives the duck's bob/swim animation

duck_x: f32 = 180
duck_speed: f32 = 24 // px/sec; sign flips when duck_x hits the pond edges

// ------------------------------------------------------------------------------------------------
// Entry point
// ------------------------------------------------------------------------------------------------
@(export)
batchiness_main :: proc "c" () {
	context = runtime.default_context()

	canvas_h := batch.canvas_create(batch.get_element_by_id("app"), CANVAS_W, CANVAS_H)
	ctx = batch.canvas_get_context(canvas_h)

	bake_sprites()

	batch.start_animation_loop(CB_ANIMATION_TICK)
}

// ------------------------------------------------------------------------------------------------
@(export)
batchiness_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case CB_ANIMATION_TICK:
		draw_frame()
	}
}

// ------------------------------------------------------------------------------------------------
// bake_sprites records the tree and duck artwork ONCE into offscreen sprite canvases
// (bake_begin/bake_end), then flushes that recording immediately. From then on, every frame just
// re-blits the finished sprites (draw_sprite) instead of re-encoding the paths/arcs that make up
// their artwork — the per-frame buffer stays tiny regardless of how detailed the art is.
bake_sprites :: proc() {
	batch.reset(&cmd)

	// --- Tree: a brown trunk + three overlapping green circles for the canopy. ---
	batch.bake_begin(&cmd, SPRITE_TREE, TREE_W, TREE_H)

	trunk_w := f32(TREE_W) * 0.18
	trunk_h := f32(TREE_H) * 0.32
	batch.set_fill(&cmd, "#5b3a22")
	batch.fill_rect(&cmd, f32(TREE_W) / 2 - trunk_w / 2, f32(TREE_H) - trunk_h, trunk_w, trunk_h)

	canopy_colours := [3]string{"#1f5c2e", "#2c7a3d", "#3f9650"}
	canopy_y := f32(TREE_H) - trunk_h
	for i in 0 ..< 3 {
		r := f32(TREE_W) * (0.30 - f32(i) * 0.03)
		ox := f32(TREE_W) / 2 + f32(i - 1) * f32(TREE_W) * 0.14
		oy := canopy_y - f32(i) * f32(TREE_H) * 0.12 - r * 0.5
		batch.set_fill(&cmd, canopy_colours[i])
		batch.begin_path(&cmd)
		batch.arc(&cmd, ox, oy, r, 0, math.TAU)
		batch.fill(&cmd)
	}

	batch.bake_end(&cmd)

	// --- Duck: white body + wing ellipses, a round head, an orange beak path, a dark eye dot. ---
	batch.bake_begin(&cmd, SPRITE_DUCK, DUCK_W, DUCK_H)

	fw := f32(DUCK_W)
	fh := f32(DUCK_H)

	batch.set_fill(&cmd, "#fefefe")
	batch.begin_path(&cmd)
	batch.ellipse(&cmd, fw * 0.5, fh * 0.62, fw * 0.40, fh * 0.34, 0, 0, math.TAU)
	batch.fill(&cmd)

	batch.set_fill(&cmd, "#e4e4e4")
	batch.begin_path(&cmd)
	batch.ellipse(&cmd, fw * 0.44, fh * 0.60, fw * 0.19, fh * 0.18, 0.3, 0, math.TAU)
	batch.fill(&cmd)

	batch.set_fill(&cmd, "#fefefe")
	batch.begin_path(&cmd)
	batch.arc(&cmd, fw * 0.78, fh * 0.32, fh * 0.24, 0, math.TAU)
	batch.fill(&cmd)

	batch.set_fill(&cmd, "#f5a623")
	batch.begin_path(&cmd)
	batch.move_to(&cmd, fw * 0.94, fh * 0.30)
	batch.line_to(&cmd, fw * 1.04, fh * 0.34)
	batch.line_to(&cmd, fw * 0.94, fh * 0.40)
	batch.close_path(&cmd)
	batch.fill(&cmd)

	batch.set_fill(&cmd, "#222222")
	batch.begin_path(&cmd)
	batch.arc(&cmd, fw * 0.83, fh * 0.28, fh * 0.035, 0, math.TAU)
	batch.fill(&cmd)

	batch.bake_end(&cmd)

	batch.flush(ctx, &cmd)
}

// ------------------------------------------------------------------------------------------------
// draw_frame re-records the whole scene into `cmd` and flushes it with ONE foreign call. This is
// the steady-state per-frame cost: a sky gradient, a ground fill, a pond gradient, one sprite
// blit for the tree, and one sprite blit for the duck — six draw commands, one bridge crossing.
draw_frame :: proc() {
	time += 1.0 / 60.0

	batch.reset(&cmd)

	// Sky: a vertical gradient from dawn orange to pale blue.
	batch.linear_gradient(&cmd, 0, 0, 0, 0, HORIZON_Y)
	batch.add_color_stop(&cmd, 0, 0.0, "#ffd9a0")
	batch.add_color_stop(&cmd, 0, 1.0, "#9fd4ff")
	batch.use_gradient_fill(&cmd, 0)
	batch.fill_rect(&cmd, 0, 0, CANVAS_W, HORIZON_Y)

	// Ground: flat green fill below the horizon.
	batch.set_fill(&cmd, "#3f8c3f")
	batch.fill_rect(&cmd, 0, HORIZON_Y, CANVAS_W, CANVAS_H - HORIZON_Y)

	// Pond: a gradient-filled ellipse sitting on the ground.
	batch.linear_gradient(&cmd, 1, 0, POND_CY - POND_RY, 0, POND_CY + POND_RY)
	batch.add_color_stop(&cmd, 1, 0.0, "#bfe6ff")
	batch.add_color_stop(&cmd, 1, 1.0, "#3f8fc4")
	batch.use_gradient_fill(&cmd, 1)
	batch.begin_path(&cmd)
	batch.ellipse(&cmd, POND_CX, POND_CY, POND_RX, POND_RY, 0, 0, math.TAU)
	batch.fill(&cmd)

	// Tree: one sprite blit, no re-encoding of its artwork.
	batch.draw_sprite(&cmd, SPRITE_TREE, TREE_X - TREE_W / 2, HORIZON_Y - TREE_H)

	// Duck: swims back and forth across the pond, bobbing gently on a sine wave. Flips
	// horizontally (negative width) when swimming left.
	duck_x += duck_speed * (1.0 / 60.0)
	if duck_x < DUCK_MIN_X {
		duck_x = DUCK_MIN_X
		duck_speed = -duck_speed
	}
	if duck_x > DUCK_MAX_X {
		duck_x = DUCK_MAX_X
		duck_speed = -duck_speed
	}
	bob := math.sin(time * 2.4) * 4.0

	dw: f32 = DUCK_W
	if duck_speed < 0 {
		dw = -DUCK_W
	}
	batch.draw_sprite_scaled(
		&cmd,
		SPRITE_DUCK,
		duck_x - DUCK_W / 2,
		POND_CY + bob - DUCK_H / 2,
		dw,
		DUCK_H,
	)

	batch.flush(ctx, &cmd)
}
