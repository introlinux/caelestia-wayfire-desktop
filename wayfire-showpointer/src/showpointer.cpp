/*
 * showpointer: draw the audience's attention to the mouse pointer.
 *
 * Provides four independent visual effects, all centered on the pointer:
 *
 *   - converge: a burst of rings which shrink towards the pointer and vanish
 *     when they reach it. Meant to answer "where is my cursor?" at a glance.
 *   - spotlight: dims the whole layout except a soft-edged circle following
 *     the pointer.
 *   - halo: a persistent glow stuck to the pointer, optionally pulsating.
 *   - ripple: a ring expanding from every pointer button press, with a
 *     separate color per button.
 *
 * The bursts can be triggered by an activator binding or by shaking the
 * pointer (as in "find my cursor" implementations elsewhere); halo and
 * spotlight are toggled on and off; ripples follow button presses directly.
 *
 * Implementation notes: no shaders are used, so the plugin works on every
 * wlroots renderer and not just GLES2. Instead, each effect renders a single
 * cairo-baked texture which is scaled per frame via render_pass_t::add_texture
 * and, for the spotlight, four plain rectangles for the area outside the hole.
 * Textures are re-baked only when the corresponding options or the output
 * scale change, never per frame.
 *
 * While an effect runs the output is damaged in full every frame. The effects
 * are translucent, so any region not repainted from scratch would accumulate
 * the same texture until it turned solid; and a pointer living in a hardware
 * cursor plane emits no damage of its own, so partial damage would also stall
 * the animation whenever the pointer stood still.
 *
 * The MIT License (MIT)
 * Copyright (c) 2026 caelestia-wayfire-desktop
 */

#include <algorithm>
#include <cmath>
#include <deque>
#include <list>

#include <cairo.h>
#include <linux/input-event-codes.h>

#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/plugins/common/cairo-util.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/region.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <wayfire/util/duration.hpp>

namespace wf
{
namespace showpointer
{
/**
 * Emitted on the shared state whenever the set of running effects changes, so
 * that per-output instances know when to attach and detach their render hooks.
 */
struct state_changed_signal
{};

/** Upper bound on concurrently animating click ripples. */
static constexpr size_t MAX_RIPPLES = 16;

/** Fraction of the burst's lifetime that each converge ring is delayed by. */
static constexpr double RING_STAGGER = 0.18;

/** How much of its starting radius a converging ring gives up before fading. */
static constexpr double RING_CONVERGE = 0.82;

/** Below this alpha an effect is considered invisible and is skipped. */
static constexpr double MIN_VISIBLE_ALPHA = 0.001;

/**
 * A cairo-baked texture, remembering the parameters it was baked with so that
 * it is only re-created when something actually changed.
 */
struct baked_texture_t
{
    wf::owned_texture_t texture;

    bool valid = false;
    float scale = 0;
    double radius = 0;
    double extra  = 0;
    wf::color_t color = {0, 0, 0, 0};

    bool matches(float scale, double radius, double extra, const wf::color_t& color) const
    {
        return valid && (this->scale == scale) && (this->radius == radius) &&
               (this->extra == extra) && (this->color == color);
    }

    void store(wf::owned_texture_t tex, float scale, double radius, double extra,
        const wf::color_t& color)
    {
        this->texture = std::move(tex);
        this->valid   = true;
        this->scale   = scale;
        this->radius  = radius;
        this->extra   = extra;
        this->color   = color;
    }
};

/**
 * Create a square ARGB32 surface, run @painter on it and upload the result.
 * The surface itself is discarded, only the texture is kept.
 */
template<class Painter>
static wf::owned_texture_t bake_square(int size, const Painter& painter)
{
    size = std::max(size, 2);

    auto surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    auto cr = cairo_create(surface);

    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    painter(cr, size);
    cairo_surface_flush(surface);

    wf::owned_texture_t result{surface};

    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return result;
}

/**
 * Bake a ring which touches the edges of the texture, with soft inner and
 * outer edges.
 *
 * @param size The side of the texture, in pixels.
 * @param width The stroke width of the ring, in pixels.
 */
static wf::owned_texture_t bake_ring(int size, double width, const wf::color_t& color)
{
    return bake_square(size, [&] (cairo_t *cr, int side)
    {
        const double c = side / 2.0;
        /* Leave a pixel of slack so that the outer feather is not clipped. */
        const double outer  = c - 1.0;
        const double stroke = std::clamp(width, 1.0, outer);
        const double inner  = outer - stroke;

        /* Two stops of the same color rather than one: a single mid stop
         * would make the fully saturated color exist at exactly one radius,
         * which renders as a hairline no matter how wide the stroke is. The
         * dark outline flanking the band keeps a light-colored ring readable
         * over light wallpapers and window content. */
        const double outline_alpha = color.a * 0.6;

        auto pattern = cairo_pattern_create_radial(c, c, 0, c, c, c);
        cairo_pattern_add_color_stop_rgba(pattern, inner / c, 0, 0, 0, 0);
        cairo_pattern_add_color_stop_rgba(pattern, (inner + stroke * 0.18) / c,
            0, 0, 0, outline_alpha);
        cairo_pattern_add_color_stop_rgba(pattern, (inner + stroke * 0.30) / c,
            color.r, color.g, color.b, color.a);
        cairo_pattern_add_color_stop_rgba(pattern, (inner + stroke * 0.70) / c,
            color.r, color.g, color.b, color.a);
        cairo_pattern_add_color_stop_rgba(pattern, (inner + stroke * 0.82) / c,
            0, 0, 0, outline_alpha);
        cairo_pattern_add_color_stop_rgba(pattern, outer / c, 0, 0, 0, 0);
        cairo_set_source(cr, pattern);
        cairo_paint(cr);
        cairo_pattern_destroy(pattern);
    });
}

/** Bake a glow: strongest in the center, fading out towards the edges. */
static wf::owned_texture_t bake_glow(int size, const wf::color_t& color)
{
    return bake_square(size, [&] (cairo_t *cr, int side)
    {
        const double c = side / 2.0;

        /* Hold the color over the inner half before falling off, otherwise the
         * glow averages out to something far fainter than the configured
         * alpha would suggest. */
        auto pattern = cairo_pattern_create_radial(c, c, 0, c, c, c - 1.0);
        cairo_pattern_add_color_stop_rgba(pattern, 0.0, color.r, color.g, color.b, color.a);
        cairo_pattern_add_color_stop_rgba(pattern, 0.45, color.r, color.g, color.b,
            color.a * 0.92);
        cairo_pattern_add_color_stop_rgba(pattern, 0.75, color.r, color.g, color.b,
            color.a * 0.45);
        cairo_pattern_add_color_stop_rgba(pattern, 1.0, color.r, color.g, color.b, 0);
        cairo_set_source(cr, pattern);
        cairo_paint(cr);
        cairo_pattern_destroy(pattern);
    });
}

/**
 * Bake the spotlight hole: transparent up to @radius, fading to the dim color
 * over @feather pixels and staying dim beyond that. The pad extend mode makes
 * sure the corners of the texture are dim as well.
 */
static wf::owned_texture_t bake_hole(double radius, double feather, const wf::color_t& color)
{
    const int size = int(std::ceil((radius + feather) * 2));

    return bake_square(size, [&] (cairo_t *cr, int side)
    {
        const double c = side / 2.0;

        auto pattern = cairo_pattern_create_radial(c, c, 0, c, c, c);
        cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD);
        cairo_pattern_add_color_stop_rgba(pattern, std::min(radius / c, 1.0),
            color.r, color.g, color.b, 0);
        cairo_pattern_add_color_stop_rgba(pattern, 1.0, color.r, color.g, color.b, color.a);
        cairo_set_source(cr, pattern);
        cairo_paint(cr);
        cairo_pattern_destroy(pattern);
    });
}

/** A click ripple, frozen at the position where the button was pressed. */
struct ripple_t
{
    /** Layout coordinates of the press. */
    wf::pointf_t at = {0, 0};
    /** Which of the per-button colors this ripple uses. */
    int slot = 0;
    wf::color_t color = {0, 0, 0, 0};
    wf::animation::simple_animation_t progress;

    ripple_t(wf::option_sptr_t<wf::animation_description_t> duration) : progress(duration)
    {}
};

/**
 * Detects a "shake" of the pointer: several quick direction reversals along
 * the X axis, each preceded by a minimum amount of travel, within a time
 * window.
 *
 * Sampling absolute cursor positions rather than relative event deltas keeps
 * this working for touchpads and tablets as well as for plain mice.
 */
class shake_detector_t
{
    bool have_sample = false;
    wf::pointf_t last_pos = {0, 0};
    int direction = 0;
    double travel = 0;
    std::deque<uint32_t> reversals;

  public:
    void reset()
    {
        have_sample = false;
        direction   = 0;
        travel = 0;
        reversals.clear();
    }

    /**
     * Feed the current cursor position.
     * @return Whether a shake has just been completed.
     */
    bool sample(wf::pointf_t pos, double min_distance, int needed, uint32_t timeout)
    {
        const double dx  = pos.x - last_pos.x;
        const bool first = !have_sample;

        last_pos    = pos;
        have_sample = true;
        if (first || (std::abs(dx) < 1.0))
        {
            return false;
        }

        const int dir = dx > 0 ? 1 : -1;
        if (dir == direction)
        {
            travel += std::abs(dx);
            return false;
        }

        const uint32_t now = wf::get_current_time();
        if (travel >= min_distance)
        {
            reversals.push_back(now);
        } else if (direction != 0)
        {
            /* A too short leg in between breaks the sequence. */
            reversals.clear();
        }

        direction = dir;
        travel    = std::abs(dx);

        while (!reversals.empty() && (now - reversals.front() > timeout))
        {
            reversals.pop_front();
        }

        if ((int)reversals.size() >= needed)
        {
            reset();
            return true;
        }

        return false;
    }
};

/**
 * State shared by all outputs: the effects are global because the pointer is
 * global, while rendering necessarily happens per output.
 */
class showpointer_global_t : public wf::signal::provider_t
{
  public:
    wf::option_wrapper_t<wf::color_t> ring_color{"showpointer/ring_color"};
    wf::option_wrapper_t<int> ring_radius{"showpointer/ring_radius"};
    wf::option_wrapper_t<int> ring_width{"showpointer/ring_width"};
    wf::option_wrapper_t<int> ring_count{"showpointer/ring_count"};
    wf::option_wrapper_t<wf::animation_description_t> burst_duration{
        "showpointer/burst_duration"};

    wf::option_wrapper_t<wf::color_t> halo_color{"showpointer/halo_color"};
    wf::option_wrapper_t<int> halo_radius{"showpointer/halo_radius"};
    wf::option_wrapper_t<double> halo_pulse{"showpointer/halo_pulse"};
    wf::option_wrapper_t<int> halo_pulse_period{"showpointer/halo_pulse_period"};
    wf::option_wrapper_t<wf::animation_description_t> toggle_duration{
        "showpointer/toggle_duration"};

    wf::option_wrapper_t<wf::color_t> spotlight_color{"showpointer/spotlight_color"};
    wf::option_wrapper_t<int> spotlight_radius{"showpointer/spotlight_radius"};
    wf::option_wrapper_t<int> spotlight_feather{"showpointer/spotlight_feather"};

    wf::option_wrapper_t<bool> ripple_enabled{"showpointer/ripple_enabled"};
    wf::option_wrapper_t<int> ripple_radius{"showpointer/ripple_radius"};
    wf::option_wrapper_t<int> ripple_width{"showpointer/ripple_width"};
    wf::option_wrapper_t<wf::color_t> ripple_color_left{"showpointer/ripple_color_left"};
    wf::option_wrapper_t<wf::color_t> ripple_color_right{"showpointer/ripple_color_right"};
    wf::option_wrapper_t<wf::color_t> ripple_color_middle{"showpointer/ripple_color_middle"};
    wf::option_wrapper_t<wf::animation_description_t> ripple_duration{
        "showpointer/ripple_duration"};

    wf::option_wrapper_t<bool> shake_enabled{"showpointer/shake_enabled"};
    wf::option_wrapper_t<int> shake_reversals{"showpointer/shake_reversals"};
    wf::option_wrapper_t<int> shake_distance{"showpointer/shake_distance"};
    wf::option_wrapper_t<int> shake_timeout{"showpointer/shake_timeout"};

    bool halo_on = false;
    bool spotlight_on = false;

    wf::animation::simple_animation_t burst{burst_duration};
    wf::animation::simple_animation_t halo_fade{toggle_duration};
    wf::animation::simple_animation_t spotlight_fade{toggle_duration};
    std::list<ripple_t> ripples;

    showpointer_global_t()
    {
        burst.set(0, 0);
        halo_fade.set(0, 0);
        spotlight_fade.set(0, 0);

        wf::get_core().connect(&on_pointer_motion);
        wf::get_core().connect(&on_pointer_motion_absolute);
        wf::get_core().connect(&on_tablet_axis);
        wf::get_core().connect(&on_button);

        /* Appearance changes must reach the screen even if nothing is
         * currently animating, for example while the halo is held on. */
        ring_color.set_callback(notify_cb);
        halo_color.set_callback(notify_cb);
        halo_radius.set_callback(notify_cb);
        spotlight_color.set_callback(notify_cb);
        spotlight_radius.set_callback(notify_cb);
        spotlight_feather.set_callback(notify_cb);
        shake_enabled.set_callback(shake_option_cb);
    }

    ~showpointer_global_t()
    {
        on_pointer_motion.disconnect();
        on_pointer_motion_absolute.disconnect();
        on_tablet_axis.disconnect();
        on_button.disconnect();
    }

    /**
     * Whether an animation is still under way.
     *
     * Note that duration_t::running() must NOT be used for this: it is not a
     * plain query, it clears the running flag the first time it reports a
     * finished animation. Calling it more than once per frame - or inside a
     * short-circuiting || chain, where whether it runs at all depends on the
     * other effects - makes the result depend on the call order. progress()
     * is a const query and reads 1.0 both before the first start and after the
     * end, which is exactly what is needed here.
     */
    static bool animating(const wf::animation::simple_animation_t& anim)
    {
        return anim.progress() < 1.0;
    }

    /** Whether anything at all has to be drawn right now. */
    bool is_active() const
    {
        return animating(burst) || !ripples.empty() ||
               halo_on || spotlight_on ||
               animating(halo_fade) || animating(spotlight_fade);
    }

    void start_burst()
    {
        burst.animate(0.0, 1.0);
        notify();
    }

    void toggle_halo()
    {
        halo_on = !halo_on;
        halo_fade.animate(halo_on ? 1.0 : 0.0);
        notify();
    }

    void toggle_spotlight()
    {
        spotlight_on = !spotlight_on;
        spotlight_fade.animate(spotlight_on ? 1.0 : 0.0);
        notify();
    }

    /** Drop ripples which have finished animating. Called once per frame. */
    void expire_ripples()
    {
        ripples.remove_if([] (ripple_t& ripple)
        {
            return !animating(ripple.progress);
        });
    }

    void notify()
    {
        state_changed_signal ev;
        this->emit(&ev);
    }

  private:
    wf::config::option_base_t::updated_callback_t notify_cb = [=] ()
    {
        notify();
    };

    wf::config::option_base_t::updated_callback_t shake_option_cb = [=] ()
    {
        shake.reset();
    };

    shake_detector_t shake;

    void on_motion()
    {
        sample_shake();
    }

    void sample_shake()
    {
        if (!shake_enabled)
        {
            return;
        }

        if (shake.sample(wf::get_core().get_cursor_position(), shake_distance,
            std::max(2, int(shake_reversals)), uint32_t(std::max(1, int(shake_timeout)))))
        {
            start_burst();
        }
    }

    void add_ripple(uint32_t button)
    {
        if (!ripple_enabled)
        {
            return;
        }

        int slot = 0;
        if (button == BTN_RIGHT)
        {
            slot = 1;
        } else if (button == BTN_MIDDLE)
        {
            slot = 2;
        }

        const wf::color_t colors[3] = {
            ripple_color_left, ripple_color_right, ripple_color_middle
        };

        while (ripples.size() >= MAX_RIPPLES)
        {
            ripples.pop_front();
        }

        auto& ripple = ripples.emplace_back(ripple_duration);
        ripple.at    = wf::get_core().get_cursor_position();
        ripple.slot  = slot;
        ripple.color = colors[slot];
        ripple.progress.animate(0.0, 1.0);
        notify();
    }

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_motion_event>>
    on_pointer_motion = [=] (auto)
    {
        on_motion();
    };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_motion_absolute_event>>
    on_pointer_motion_absolute = [=] (auto)
    {
        on_motion();
    };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_tablet_tool_axis_event>>
    on_tablet_axis = [=] (auto)
    {
        on_motion();
    };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_button_event>>
    on_button = [=] (wf::post_input_event_signal<wlr_pointer_button_event> *ev)
    {
        if (ev->event->state == WL_POINTER_BUTTON_STATE_PRESSED)
        {
            add_ripple(ev->event->button);
        }
    };
};

class wayfire_showpointer : public wf::per_output_plugin_instance_t
{
    wf::shared_data::ref_ptr_t<showpointer_global_t> global;

    bool hooks_set = false;

    baked_texture_t ring_tex;
    baked_texture_t glow_tex;
    baked_texture_t hole_tex;
    baked_texture_t ripple_tex[3];

  public:
    void init() override
    {
        output->add_activator(
            wf::option_wrapper_t<wf::activatorbinding_t>{"showpointer/attention"},
            &attention_cb);
        output->add_activator(
            wf::option_wrapper_t<wf::activatorbinding_t>{"showpointer/toggle_halo"},
            &toggle_halo_cb);
        output->add_activator(
            wf::option_wrapper_t<wf::activatorbinding_t>{"showpointer/toggle_spotlight"},
            &toggle_spotlight_cb);

        global->connect(&on_state_changed);
    }

    void fini() override
    {
        output->rem_binding(&attention_cb);
        output->rem_binding(&toggle_halo_cb);
        output->rem_binding(&toggle_spotlight_cb);
        on_state_changed.disconnect();
        unset_hooks();
        output->render->damage_whole();
    }

  private:
    wf::activator_callback attention_cb = [=] (auto)
    {
        global->start_burst();
        return true;
    };

    wf::activator_callback toggle_halo_cb = [=] (auto)
    {
        global->toggle_halo();
        return true;
    };

    wf::activator_callback toggle_spotlight_cb = [=] (auto)
    {
        global->toggle_spotlight();
        return true;
    };

    wf::signal::connection_t<state_changed_signal> on_state_changed = [=] (auto)
    {
        if (global->is_active())
        {
            set_hooks();
        }

        /* Hooks are detached from the damage hook itself, once the last effect
         * has actually finished animating. */
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

    /** The pointer position in this output's local coordinates. */
    wf::pointf_t local_cursor() const
    {
        auto og = output->get_layout_geometry();
        auto gc = wf::get_core().get_cursor_position();
        return {gc.x - og.x, gc.y - og.y};
    }

    bool cursor_on_output() const
    {
        auto gc = wf::get_core().get_cursor_position();
        return output->get_layout_geometry() & wf::point_t{int(gc.x), int(gc.y)};
    }

    /** A square of side 2 * radius centered at @center, rounded outwards. */
    static wf::geometry_t box_around(wf::pointf_t center, double radius)
    {
        const int x = int(std::floor(center.x - radius));
        const int y = int(std::floor(center.y - radius));
        const int w = int(std::ceil(center.x + radius)) - x;
        const int h = int(std::ceil(center.y + radius)) - y;
        return {x, y, w, h};
    }

    static wlr_fbox fbox_around(wf::pointf_t center, double radius)
    {
        return {center.x - radius, center.y - radius, radius * 2, radius * 2};
    }

    /** The current halo radius, including the pulse. */
    double halo_current_radius()
    {
        const double base   = global->halo_radius;
        const double amount = global->halo_pulse;
        const int period    = global->halo_pulse_period;
        if ((amount <= 0) || (period <= 0))
        {
            return base;
        }

        const double phase = (wf::get_current_time() % uint32_t(period)) / double(period);
        return base * (1.0 + amount * std::sin(phase * 2 * M_PI));
    }

    wf::effect_hook_t damage_hook = [=] ()
    {
        global->expire_ripples();

        /* Damage the whole output on every frame an effect is running.
         *
         * Partial damage is tempting but wrong here: the effects are drawn
         * translucently over the scene, so any area which is not repainted
         * from scratch would accumulate the same texture frame after frame
         * until it turned solid. On top of that, a pointer which sits in a
         * hardware cursor plane produces no damage of its own, so nothing
         * would drive the animation forward while the pointer is still.
         *
         * The cost is bounded: bursts and ripples last well under a second,
         * and the halo and the spotlight are explicit presentation modes. */
        output->render->damage(output->get_relative_geometry());

        if (!global->is_active())
        {
            /* Everything finished. The damage above already scheduled the
             * repaint which clears the last frame. */
            unset_hooks();
        }
    };

    /** Re-bake @tex unless it already matches the requested parameters. */
    static wf::texture_t get_ring(baked_texture_t& tex, float scale, double radius,
        double width, const wf::color_t& color)
    {
        if (!tex.matches(scale, radius, width, color))
        {
            tex.store(bake_ring(int(std::ceil(radius * 2 * scale)), width * scale, color),
                scale, radius, width, color);
        }

        return tex.texture.get_texture();
    }

    wf::effect_hook_t overlay_hook = [=] ()
    {
        auto pass = output->render->get_current_pass();
        auto fb   = output->render->get_target_framebuffer();
        auto og   = output->get_relative_geometry();
        auto olg  = output->get_layout_geometry();
        const float scale = fb.scale;

        /* The damage handed to add_texture()/add_rect() must be in logical
         * output coordinates: the render pass converts it to framebuffer
         * coordinates itself (render.cpp, framebuffer_region_from_geometry_region).
         *
         * get_swap_damage() is NOT in those units - render-manager converts it
         * to buffer coordinates before returning it (render-manager.cpp, end of
         * start_output_pass), so intersecting it with the logical output
         * geometry mixes the two systems. On a scale-2 output that intersection
         * clips against a rectangle half the size of the buffer in each axis.
         *
         * The damage hook damages the whole output every frame anyway, so the
         * correct and simplest clip is the output itself, in logical units. */
        const wf::region_t damage{og};

        const bool on_output = cursor_on_output();
        const auto pos = local_cursor();

        render_spotlight(pass, fb, og, damage, scale, on_output, pos);

        if (on_output)
        {
            render_halo(pass, fb, damage, scale, pos);
            render_burst(pass, fb, damage, scale, pos);
        }

        for (auto& ripple : global->ripples)
        {
            render_ripple(pass, fb, damage, scale, ripple, olg);
        }
    };

    void render_spotlight(wf::render_pass_t *pass, const wf::render_target_t& fb,
        wf::geometry_t og, const wf::region_t& damage, float scale, bool on_output,
        wf::pointf_t pos)
    {
        const double fade = global->spotlight_fade;
        if (fade <= MIN_VISIBLE_ALPHA)
        {
            return;
        }

        const wf::color_t dim = global->spotlight_color;
        const double radius   = global->spotlight_radius;
        const double feather  = std::max(1.0, double(global->spotlight_feather));

        /* add_rect expects a premultiplied color. */
        const auto premultiplied = [] (wf::color_t c, double alpha)
        {
            const double a = c.a * alpha;
            return wf::color_t{c.r * a, c.g * a, c.b * a, a};
        };

        if (!on_output)
        {
            pass->add_rect(premultiplied(dim, fade), fb, og, damage);
            return;
        }

        if (!hole_tex.matches(scale, radius, feather, dim))
        {
            hole_tex.store(bake_hole(radius * scale, feather * scale, dim),
                scale, radius, feather, dim);
        }

        /* The hole texture and the rectangles around it must share exactly the
         * same edges, so the texture is placed on the same integer box the
         * rectangles are derived from. Drawing it on the unrounded float box
         * instead would leave a hairline of undimmed pixels along the seam. */
        const double outer = radius + feather;
        const auto hole    = box_around(pos, outer);
        pass->add_texture(hole_tex.texture.get_texture(), fb, hole, damage, fade);

        /* Dim everything around the hole with four plain rectangles. */
        const wf::geometry_t around[4] = {
            {og.x, og.y, og.width, hole.y - og.y},
            {og.x, hole.y + hole.height, og.width, og.y + og.height - hole.y - hole.height},
            {og.x, hole.y, hole.x - og.x, hole.height},
            {hole.x + hole.width, hole.y, og.x + og.width - hole.x - hole.width, hole.height},
        };

        for (auto& rect : around)
        {
            if ((rect.width > 0) && (rect.height > 0))
            {
                pass->add_rect(premultiplied(dim, fade), fb, rect, damage);
            }
        }
    }

    void render_halo(wf::render_pass_t *pass, const wf::render_target_t& fb,
        const wf::region_t& damage, float scale, wf::pointf_t pos)
    {
        const double fade = global->halo_fade;
        if (fade <= MIN_VISIBLE_ALPHA)
        {
            return;
        }

        const double base = global->halo_radius;
        const wf::color_t color = global->halo_color;

        if (!glow_tex.matches(scale, base, 0, color))
        {
            glow_tex.store(bake_glow(int(std::ceil(base * 2 * scale)), color),
                scale, base, 0, color);
        }

        pass->add_texture(glow_tex.texture.get_texture(), fb,
            fbox_around(pos, halo_current_radius()), damage, fade);
    }

    void render_burst(wf::render_pass_t *pass, const wf::render_target_t& fb,
        const wf::region_t& damage, float scale, wf::pointf_t pos)
    {
        if (!showpointer_global_t::animating(global->burst))
        {
            return;
        }

        const double radius = global->ring_radius;
        const int count     = std::max(1, int(global->ring_count));
        const double p = global->burst;

        const auto texture = get_ring(ring_tex, scale, radius, global->ring_width,
            global->ring_color);

        /* Each ring lags behind the previous one, so that they arrive at the
         * pointer one after another. */
        const double span = 1.0 - RING_STAGGER * (count - 1);
        for (int i = 0; i < count; i++)
        {
            const double t = std::clamp((p - RING_STAGGER * i) / span, 0.0, 1.0);
            if ((t <= 0.0) || (t >= 1.0))
            {
                continue;
            }

            /* Fade in quickly, stay fully opaque for most of the travel and
             * only fade out right at the end. Easing the alpha over the whole
             * span instead (a sine, say) peaks in the middle and leaves the
             * ring invisible exactly where it matters most: arriving at the
             * pointer. */
            const double alpha = t < 0.12 ? t / 0.12 :
                (t > 0.85 ? (1.0 - t) / 0.15 : 1.0);

            /* Shrink towards the pointer, but stop short of zero: the stroke
             * of a scaled-down texture thins out with it, so a ring converging
             * all the way to a point fades into an invisible hairline right
             * where it should be most legible. */
            const double r = radius * (1.0 - t * RING_CONVERGE);
            pass->add_texture(texture, fb, fbox_around(pos, r), damage, alpha);
        }
    }

    void render_ripple(wf::render_pass_t *pass, const wf::render_target_t& fb,
        const wf::region_t& damage, float scale, ripple_t& ripple, wf::geometry_t olg)
    {
        const double t = ripple.progress;
        const double radius = global->ripple_radius;

        const auto texture = get_ring(ripple_tex[ripple.slot], scale, radius,
            global->ripple_width, ripple.color);

        /* Start from a fraction of the radius rather than from zero, so the
         * ring is a ring from the first frame instead of a dot. */
        pass->add_texture(texture, fb,
            fbox_around({ripple.at.x - olg.x, ripple.at.y - olg.y},
                radius * (0.15 + 0.85 * t)),
            damage, 1.0 - t);
    }
};
}
}

DECLARE_WAYFIRE_PLUGIN(wf::per_output_plugin_t<wf::showpointer::wayfire_showpointer>);
