/*
 * intro: cinematic session-start reveal.
 *
 * From the very first composited frame every output is covered by an opaque
 * curtain (black by default), so the desktop never flashes while the shell,
 * the wallpaper and the panels are still loading. When the session is ready
 * the curtain opens and reveals the desktop:
 *
 *   - split: the curtain parts in two horizontal halves which slide off the
 *     top and bottom edges, movie style.
 *   - iris: a circle opens from the center of the screen and grows until the
 *     whole desktop is visible.
 *
 * The reveal is triggered over the Wayfire IPC socket ("intro/reveal",
 * registered on the shared method repository, so it works with the plain
 * "ipc" plugin loaded), normally by the shell once its wallpaper is on
 * screen. A configurable timeout acts as a safety net: if nothing calls
 * intro/reveal (the shell crashed, IPC is disabled...), the curtain opens on
 * its own rather than leaving the session black forever.
 *
 * An optional activator ("replay") and the "intro/replay" IPC method re-run
 * the whole effect on demand, which is also the practical way to tune the
 * options live without restarting the session.
 *
 * Implementation notes: no shaders are used, so the plugin works on every
 * wlroots renderer, not just GLES2 (same approach as showpointer). The split
 * curtains are plain rectangles; the iris is a single cairo-baked "hole"
 * texture (transparent center feathering out to the curtain color, pad
 * extend) scaled per frame, with four rectangles covering the area around it.
 * While the reveal animates, the output is damaged in full every frame; while
 * the curtain just holds, repaints triggered by clients underneath are simply
 * covered again, at no extra cost.
 *
 * The MIT License (MIT)
 * Copyright (c) 2026 caelestia-wayfire-desktop
 */

#include <algorithm>
#include <cmath>

#include <cairo.h>

#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/plugins/common/cairo-util.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/region.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/util.hpp>
#include <wayfire/util/duration.hpp>

namespace wf
{
namespace intro
{
/** Emitted on the shared state whenever the phase changes. */
struct state_changed_signal
{};

/** How long a replay holds the curtain before re-opening it, in ms. */
static constexpr uint32_t REPLAY_HOLD_MS = 500;

/**
 * The baked iris texture: transparent up to BAKE_RADIUS, feathering out to
 * the curtain color over BAKE_FEATHER, curtain color beyond (pad extend, so
 * the corners are covered too). It is baked once per color and scaled per
 * frame; the feathered edge is a smooth gradient, so upscaling it keeps
 * looking right at any output size.
 */
static constexpr double BAKE_RADIUS  = 560;
static constexpr double BAKE_FEATHER = 240;

/** Fraction of the texture's half-side which is fully transparent. */
static constexpr double HOLE_INNER = BAKE_RADIUS / (BAKE_RADIUS + BAKE_FEATHER);

/** Bake the iris hole texture (same construction as showpointer's spotlight). */
static wf::owned_texture_t bake_hole(double radius, double feather, const wf::color_t& color)
{
    const int size = std::max(2, int(std::ceil((radius + feather) * 2)));

    auto surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    auto cr = cairo_create(surface);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);

    const double c = size / 2.0;
    auto pattern   = cairo_pattern_create_radial(c, c, 0, c, c, c);
    cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD);
    cairo_pattern_add_color_stop_rgba(pattern, std::min(radius / c, 1.0),
        color.r, color.g, color.b, 0);
    cairo_pattern_add_color_stop_rgba(pattern, 1.0, color.r, color.g, color.b, color.a);
    cairo_set_source(cr, pattern);
    cairo_paint(cr);
    cairo_pattern_destroy(pattern);
    cairo_surface_flush(surface);

    wf::owned_texture_t result{surface};
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return result;
}

enum class phase_t
{
    /** Curtain fully down, waiting for the reveal trigger. */
    HOLD,
    /** The reveal animation is running. */
    REVEAL,
    /** Intro over, nothing is drawn anymore. */
    DONE,
};

/**
 * State shared by all outputs: the intro is a single session-wide event, but
 * rendering necessarily happens per output (each output opens its own
 * curtain over its own geometry).
 */
class intro_global_t : public wf::signal::provider_t
{
  public:
    wf::option_wrapper_t<std::string> pattern{"intro/pattern"};
    wf::option_wrapper_t<wf::animation_description_t> duration{"intro/duration"};
    wf::option_wrapper_t<int> timeout{"intro/timeout"};
    wf::option_wrapper_t<bool> opt_hide_cursor{"intro/hide_cursor"};
    wf::option_wrapper_t<wf::color_t> color{"intro/color"};

    phase_t phase = phase_t::HOLD;
    wf::animation::simple_animation_t progress{duration};

    intro_global_t()
    {
        progress.set(0, 0);
        grab_cursor();

        ipc_repo->register_method("intro/reveal", [this] (const wf::json_t&)
        {
            start_reveal();
            return wf::ipc::json_ok();
        });
        ipc_repo->register_method("intro/replay", [this] (const wf::json_t&)
        {
            replay();
            return wf::ipc::json_ok();
        });

        /* Safety net: never leave the session black forever if nobody calls
         * intro/reveal. The timeout is read once, here: by the time anyone
         * could change it live, it has already fired or been cancelled. */
        fallback.set_timeout(uint32_t(std::max(1000, int(timeout))), [this] ()
        {
            start_reveal();
        });
    }

    ~intro_global_t()
    {
        ipc_repo->unregister_method("intro/reveal");
        ipc_repo->unregister_method("intro/replay");
        release_cursor();
    }

    /** Open the curtain. No-op unless the curtain is currently holding. */
    void start_reveal()
    {
        if (phase != phase_t::HOLD)
        {
            return;
        }

        fallback.disconnect();
        phase = phase_t::REVEAL;
        progress.animate(0.0, 1.0);
        notify();
    }

    /** Drop the curtain again and re-open it shortly after. */
    void replay()
    {
        fallback.disconnect();
        replay_hold.disconnect();

        phase = phase_t::HOLD;
        progress.set(0, 0);
        grab_cursor();
        notify();

        replay_hold.set_timeout(REPLAY_HOLD_MS, [this] ()
        {
            start_reveal();
        });
    }

    /**
     * Flip to DONE once the reveal has finished animating. Called from the
     * per-output damage hooks; guarded so that only the first caller acts.
     */
    void maybe_finish()
    {
        if ((phase == phase_t::REVEAL) && (progress.progress() >= 1.0))
        {
            phase = phase_t::DONE;
            release_cursor();
            notify();
        }
    }

    void notify()
    {
        state_changed_signal ev;
        this->emit(&ev);
    }

  private:
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;
    wf::wl_timer<false> fallback;
    wf::wl_timer<false> replay_hold;
    bool cursor_hidden = false;

    /* hide_cursor()/unhide_cursor() are refcounted in core, so the guard
     * keeps our calls strictly 1:1 however often the phases cycle. */
    void grab_cursor()
    {
        if (opt_hide_cursor && !cursor_hidden)
        {
            wf::get_core().hide_cursor();
            cursor_hidden = true;
        }
    }

    void release_cursor()
    {
        if (cursor_hidden)
        {
            wf::get_core().unhide_cursor();
            cursor_hidden = false;
        }
    }
};

class wayfire_intro : public wf::per_output_plugin_instance_t
{
    wf::shared_data::ref_ptr_t<intro_global_t> global;

    bool hooks_set = false;

    wf::owned_texture_t hole_tex;
    bool hole_valid = false;
    wf::color_t hole_color = {0, 0, 0, 0};

  public:
    void init() override
    {
        output->add_activator(
            wf::option_wrapper_t<wf::activatorbinding_t>{"intro/replay"},
            &replay_cb);
        global->connect(&on_state_changed);

        if (global->phase != phase_t::DONE)
        {
            /* The whole point: the curtain must be up before the first frame
             * this output ever presents. */
            set_hooks();
            output->render->damage_whole();
        }
    }

    void fini() override
    {
        output->rem_binding(&replay_cb);
        on_state_changed.disconnect();
        unset_hooks();
        output->render->damage_whole();
    }

  private:
    wf::activator_callback replay_cb = [=] (auto)
    {
        global->replay();
        return true;
    };

    wf::signal::connection_t<state_changed_signal> on_state_changed = [=] (auto)
    {
        if (global->phase != phase_t::DONE)
        {
            set_hooks();
        }

        /* Repaint on every phase change; the repaint after DONE is the one
         * which clears the last frame of the curtain. */
        if (hooks_set)
        {
            output->render->damage_whole();
        }
    };

    void set_hooks()
    {
        if (hooks_set)
        {
            return;
        }

        output->render->add_effect(&damage_hook, wf::OUTPUT_EFFECT_DAMAGE);
        output->render->add_effect(&overlay_hook, wf::OUTPUT_EFFECT_OVERLAY);
        hooks_set = true;
    }

    void unset_hooks()
    {
        if (!hooks_set)
        {
            return;
        }

        output->render->rem_effect(&damage_hook);
        output->render->rem_effect(&overlay_hook);
        hooks_set = false;
    }

    wf::effect_hook_t damage_hook = [=] ()
    {
        if (global->phase == phase_t::REVEAL)
        {
            /* Animating: repaint everything every frame. While merely
             * holding, this is not needed - the curtain is opaque and
             * static, so it only has to be re-drawn over whatever repaints
             * underneath it, which the overlay hook does for free. */
            output->render->damage(output->get_relative_geometry());
            global->maybe_finish();
        }

        if (global->phase == phase_t::DONE)
        {
            /* The state change signal already scheduled the clearing
             * repaint. */
            unset_hooks();
        }
    };

    /** add_rect expects a premultiplied color. */
    static wf::color_t premultiplied(wf::color_t c)
    {
        return {c.r * c.a, c.g * c.a, c.b * c.a, c.a};
    }

    /** Add @rect clipped against @og; degenerate rectangles are dropped. */
    static void add_clipped_rect(wf::render_pass_t *pass, const wf::render_target_t& fb,
        const wf::color_t& color, wf::geometry_t rect, wf::geometry_t og,
        const wf::region_t& damage)
    {
        const int x1 = std::max(rect.x, og.x);
        const int y1 = std::max(rect.y, og.y);
        const int x2 = std::min(rect.x + rect.width, og.x + og.width);
        const int y2 = std::min(rect.y + rect.height, og.y + og.height);
        if ((x2 > x1) && (y2 > y1))
        {
            pass->add_rect(color, fb, wf::geometry_t{x1, y1, x2 - x1, y2 - y1}, damage);
        }
    }

    wf::effect_hook_t overlay_hook = [=] ()
    {
        if (global->phase == phase_t::DONE)
        {
            return;
        }

        auto pass = output->render->get_current_pass();
        auto fb   = output->render->get_target_framebuffer();
        auto og   = output->get_relative_geometry();

        /* The damage handed to add_texture()/add_rect() must be in logical
         * output coordinates; do NOT intersect it with get_swap_damage(),
         * which is in buffer coordinates (see showpointer, NOTES §5.4). */
        const wf::region_t damage{og};

        /* progress() reads 1.0 before the first animate() call, so it must
         * only be consulted while actually revealing. */
        const double p = (global->phase == phase_t::HOLD) ? 0.0 :
            (double)global->progress;
        if (p >= 1.0)
        {
            return;
        }

        const wf::color_t color = premultiplied(global->color);

        if ((p <= 0.0) || (std::string(global->pattern) != "iris"))
        {
            render_split(pass, fb, og, damage, color, p);
        } else
        {
            render_iris(pass, fb, og, damage, p);
        }
    };

    void render_split(wf::render_pass_t *pass, const wf::render_target_t& fb,
        wf::geometry_t og, const wf::region_t& damage, const wf::color_t& color, double p)
    {
        if (p <= 0.0)
        {
            pass->add_rect(color, fb, og, damage);
            return;
        }

        /* Two half-height curtains sliding off the top and bottom edges. The
         * top one is the taller on odd heights, so together they always
         * cover the full output at p = 0. */
        const int top_h    = (og.height + 1) / 2;
        const int bottom_h = og.height - top_h;
        const int shift_t  = int(std::round(p * top_h));
        const int shift_b  = int(std::round(p * bottom_h));

        add_clipped_rect(pass, fb, color,
            {og.x, og.y - shift_t, og.width, top_h}, og, damage);
        add_clipped_rect(pass, fb, color,
            {og.x, og.y + og.height - bottom_h + shift_b, og.width, bottom_h},
            og, damage);
    }

    void render_iris(wf::render_pass_t *pass, const wf::render_target_t& fb,
        wf::geometry_t og, const wf::region_t& damage, double p)
    {
        const wf::color_t raw = global->color;
        if (!hole_valid || !(hole_color == raw))
        {
            hole_tex   = bake_hole(BAKE_RADIUS, BAKE_FEATHER, raw);
            hole_color = raw;
            hole_valid = true;
        }

        /* The fully transparent circle has radius p * half-diagonal, so at
         * p = 1 it just covers the farthest corners; the feathered edge
         * around it scales along and finishes fading right past them. */
        const double cx = og.x + og.width / 2.0;
        const double cy = og.y + og.height / 2.0;
        const double halfdiag = std::hypot(og.width, og.height) / 2.0;
        const double outer    = p * halfdiag / HOLE_INNER;

        /* The texture and the rectangles around it must share exactly the
         * same integer box, or a hairline of undimmed pixels shows along the
         * seam (showpointer, NOTES §3.7). */
        const int x = int(std::floor(cx - outer));
        const int y = int(std::floor(cy - outer));
        const wf::geometry_t hole = {
            x, y,
            int(std::ceil(cx + outer)) - x,
            int(std::ceil(cy + outer)) - y,
        };

        const wf::color_t color = premultiplied(raw);
        if ((hole.width < 2) || (hole.height < 2))
        {
            pass->add_rect(color, fb, og, damage);
            return;
        }

        pass->add_texture(hole_tex.get_texture(), fb, hole, damage, 1.0);

        const wf::geometry_t around[4] = {
            {og.x, og.y, og.width, hole.y - og.y},
            {og.x, hole.y + hole.height, og.width, og.y + og.height - hole.y - hole.height},
            {og.x, hole.y, hole.x - og.x, hole.height},
            {hole.x + hole.width, hole.y, og.x + og.width - hole.x - hole.width, hole.height},
        };

        for (auto& rect : around)
        {
            add_clipped_rect(pass, fb, color, rect, og, damage);
        }
    }
};
}
}

DECLARE_WAYFIRE_PLUGIN(wf::per_output_plugin_t<wf::intro::wayfire_intro>);
