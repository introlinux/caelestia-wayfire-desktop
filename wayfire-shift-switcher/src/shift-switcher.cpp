/*
 * shift-switcher: Compiz-style "card deck" raise animation for Wayfire.
 *
 * When a window that is covered by other windows gets focused, instead of
 * instantly jumping to the top of the stack it is pulled out sideways like a
 * card from a deck (while still behind), raised at the apex of the motion,
 * and slid back into place on top. This makes it easy to visually track
 * where a window went when clicking on it.
 *
 * Implementation: replaces core's default window_manager_t with a subclass
 * whose focus_raise_view() defers the actual raise to the middle of the
 * animation. All other window management behavior is inherited unchanged.
 *
 * The MIT License (MIT)
 * Copyright (c) 2026 caelestia-wayfire-desktop
 */

#include <cmath>
#include <map>

#include <wayfire/core.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/util.hpp>
#include <wayfire/util/log.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/config/option-wrapper.hpp>

namespace shift_switcher
{
static constexpr const char *TRANSFORMER_NAME = "shift-switcher";

/**
 * Window manager override: identical to the default WM, except that raising
 * a covered view is delegated to the plugin's animation. If the plugin
 * declines (nothing covers the view, it is minimized, a grab is active...),
 * the default behavior runs.
 */
class shift_wm_t : public wf::window_manager_t
{
  public:
    /* Set by the plugin. Returns true if it took care of focus+raise. */
    std::function<bool(wayfire_view, bool)> try_animate;

    void focus_raise_view(wayfire_view view, bool allow_switch_ws = false) override
    {
        LOGD("shift-switcher: focus_raise_view called, view=", view ? view->get_id() : 0);
        if (!try_animate || !try_animate(view, allow_switch_ws))
        {
            window_manager_t::focus_raise_view(view, allow_switch_ws);
        }
    }
};

class shift_switcher_t : public wf::plugin_interface_t
{
    wf::option_wrapper_t<wf::animation_description_t> duration{"shift-switcher/duration"};
    wf::option_wrapper_t<double> tilt{"shift-switcher/tilt"};
    wf::option_wrapper_t<int> margin{"shift-switcher/margin"};

    struct anim_t
    {
        wayfire_toplevel_view view;
        wf::output_t *output;
        std::shared_ptr<wf::scene::view_2d_transformer_t> transformer;
        wf::animation::simple_animation_t progress;
        wf::pointf_t offset; /* translation at the apex of the motion */
        double tilt_sign = 1.0;
        bool raised = false;
        wf::effect_hook_t hook;
        wf::wl_idle_call idle_finish;
        wf::signal::connection_t<wf::view_unmapped_signal> on_unmap;
    };

    std::map<wayfire_toplevel_view, std::unique_ptr<anim_t>> anims;
    shift_wm_t *installed_wm = nullptr;

    /* Click-to-focus reaches focus_raise_view() in the middle of the button
     * press event. If the view starts moving right away, the surface slides
     * out from under the implicit pointer grab and the client watches the
     * pointer leave whatever was pressed (e.g. its close button) before the
     * release arrives, which cancels the click. So the raise/animation of the
     * newly focused view is parked in `pending` until every pointer button
     * and touch point is up, and only then committed. */
    int pressed_count = 0;
    wayfire_toplevel_view pending = nullptr;
    wf::signal::connection_t<wf::view_unmapped_signal> pending_unmap;
    wf::wl_idle_call idle_commit;

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_button_event>> on_post_button;
    wf::signal::connection_t<wf::post_input_event_signal<wlr_touch_down_event>> on_post_touch_down;
    wf::signal::connection_t<wf::post_input_event_signal<wlr_touch_up_event>> on_post_touch_up;

  public:
    void init() override
    {
        auto wm = std::make_unique<shift_wm_t>();
        wm->try_animate = [this] (wayfire_view view, bool allow_switch_ws)
        {
            return handle_focus_raise(view, allow_switch_ws);
        };

        installed_wm = wm.get();
        wf::get_core().default_wm = std::move(wm);

        on_post_button = [this] (wf::post_input_event_signal<wlr_pointer_button_event> *ev)
        {
            if (ev->event->state == WL_POINTER_BUTTON_STATE_PRESSED)
            {
                pressed_count++;
            } else
            {
                pressed_count = std::max(0, pressed_count - 1);
                check_commit_pending();
            }
        };
        wf::get_core().connect(&on_post_button);

        on_post_touch_down = [this] (wf::post_input_event_signal<wlr_touch_down_event>*)
        {
            pressed_count++;
        };
        wf::get_core().connect(&on_post_touch_down);

        on_post_touch_up = [this] (wf::post_input_event_signal<wlr_touch_up_event>*)
        {
            pressed_count = std::max(0, pressed_count - 1);
            check_commit_pending();
        };
        wf::get_core().connect(&on_post_touch_up);

        LOGI("shift-switcher: installed window manager override");
    }

    void fini() override
    {
        clear_pending();
        while (!anims.empty())
        {
            cancel(anims.begin()->first, true);
        }

        /* Only restore if no other plugin replaced the WM after us */
        if (wf::get_core().default_wm.get() == installed_wm)
        {
            wf::get_core().default_wm = std::make_unique<wf::window_manager_t>();
        } else if (auto wm = dynamic_cast<shift_wm_t*>(wf::get_core().default_wm.get()))
        {
            wm->try_animate = nullptr;
        }
    }

  private:
    bool handle_focus_raise(wayfire_view view, bool allow_switch_ws)
    {
        auto toplevel = wf::toplevel_cast(view);
        if (!toplevel || !view->is_mapped() || toplevel->minimized || toplevel->parent)
        {
            LOGD("shift-switcher: skip (not a plain mapped toplevel)");
            return false;
        }

        auto output = toplevel->get_output();
        if (!output || !output->wset() || !view->get_keyboard_focus_surface())
        {
            LOGD("shift-switcher: skip (no output/wset/focus surface)");
            return false;
        }

        /* Do not interfere while move/scale/expo/switcher & co. hold a grab */
        if (!output->can_activate_plugin(wf::CAPABILITY_GRAB_INPUT))
        {
            LOGD("shift-switcher: skip (grab active)");
            return false;
        }

        if (anims.count(toplevel) || (pending == toplevel))
        {
            /* Already flying or queued: just make sure it keeps the focus */
            focus_no_raise(view, allow_switch_ws);
            return true;
        }

        auto offset = compute_pull_offset(toplevel);
        if (!offset)
        {
            /* Nothing covers this view, a plain raise is fine */
            LOGD("shift-switcher: skip (view not covered)");
            return false;
        }

        LOGD("shift-switcher: queueing raise of view ", toplevel->get_id());
        focus_no_raise(view, allow_switch_ws);
        set_pending(toplevel);

        /* If this was not triggered by a click there is no release to wait
         * for; the idle runs once the current input event (if any) has been
         * fully processed and commits immediately when no button is down. */
        idle_commit.run_once([this] () { check_commit_pending(); });
        return true;
    }

    void set_pending(wayfire_toplevel_view view)
    {
        clear_pending();
        pending = view;
        pending_unmap = [this] (wf::view_unmapped_signal*)
        {
            clear_pending();
        };
        view->connect(&pending_unmap);
    }

    void clear_pending()
    {
        if (pending)
        {
            pending_unmap.disconnect();
            pending = nullptr;
        }
    }

    void check_commit_pending()
    {
        if (!pending || (pressed_count > 0))
        {
            return;
        }

        auto view = pending;
        clear_pending();

        if (!view->is_mapped() || view->minimized || !view->get_output() ||
            !view->get_output()->wset())
        {
            return;
        }

        if (wf::get_core().seat->get_active_view() != view)
        {
            /* Lost the focus while waiting for the release; raising it now
             * would put an unfocused window on top */
            return;
        }

        /* The stacking may have changed while the button was held (e.g. the
         * window was moved), so recompute the escape direction now */
        auto offset = compute_pull_offset(view);
        if (!offset ||
            !view->get_output()->can_activate_plugin(wf::CAPABILITY_GRAB_INPUT))
        {
            wf::view_bring_to_front(view);
            return;
        }

        LOGD("shift-switcher: animating view ", view->get_id(),
            " offset ", offset->x, ",", offset->y);
        start_animation(view, *offset);
    }

    /* Same as the default focus_raise_view, minus the bring-to-front */
    void focus_no_raise(wayfire_view view, bool allow_switch_ws)
    {
        if (allow_switch_ws)
        {
            view->get_output()->ensure_visible(view);
        }

        wf::get_core().seat->focus_output(view->get_output());
        wf::get_core().seat->focus_view(view);
    }

    /**
     * Find the union of the views covering @view and return the smallest
     * translation which pulls @view clear of them, or nullopt if the view
     * is not covered at all.
     */
    std::optional<wf::pointf_t> compute_pull_offset(wayfire_toplevel_view view)
    {
        auto views = view->get_output()->wset()->get_views(
            wf::WSET_MAPPED_ONLY | wf::WSET_EXCLUDE_MINIMIZED | wf::WSET_SORT_STACKING);

        const auto vg = view->get_geometry();
        wf::geometry_t cover{};
        bool covered = false;

        /* Views are sorted front-to-back: everything before @view is above it */
        for (auto& v : views)
        {
            if (v == view)
            {
                break;
            }

            auto g = v->get_geometry();
            const bool overlap = (g.x < vg.x + vg.width) && (g.x + g.width > vg.x) &&
                (g.y < vg.y + vg.height) && (g.y + g.height > vg.y);
            if (!overlap)
            {
                continue;
            }

            if (!covered)
            {
                cover   = g;
                covered = true;
            } else
            {
                int x2 = std::max(cover.x + cover.width, g.x + g.width);
                int y2 = std::max(cover.y + cover.height, g.y + g.height);
                cover.x = std::min(cover.x, g.x);
                cover.y = std::min(cover.y, g.y);
                cover.width  = x2 - cover.x;
                cover.height = y2 - cover.y;
            }
        }

        if (!covered)
        {
            return {};
        }

        /* Clamp the covering box to the visible output, so that a window
         * hanging off-screen does not cause absurd travel distances */
        auto og = view->get_output()->get_relative_geometry();
        int cx1 = std::max(cover.x, og.x);
        int cy1 = std::max(cover.y, og.y);
        int cx2 = std::min(cover.x + cover.width, og.x + og.width);
        int cy2 = std::min(cover.y + cover.height, og.y + og.height);
        if ((cx1 >= cx2) || (cy1 >= cy2))
        {
            return {};
        }

        const int m = margin;
        struct candidate
        {
            int dist;
            wf::pointf_t dir;
        };

        candidate options[] = {
            {cx2 - vg.x, {1, 0}}, /* pull right */
            {(vg.x + vg.width) - cx1, {-1, 0}}, /* pull left  */
            {cy2 - vg.y, {0, 1}}, /* pull down  */
            {(vg.y + vg.height) - cy1, {0, -1}}, /* pull up    */
        };

        auto best = std::min_element(std::begin(options), std::end(options),
            [] (const candidate& a, const candidate& b) { return a.dist < b.dist; });

        double travel = best->dist + m;
        return wf::pointf_t{best->dir.x * travel, best->dir.y * travel};
    }

    void start_animation(wayfire_toplevel_view view, wf::pointf_t offset)
    {
        auto a = std::make_unique<anim_t>();
        a->view   = view;
        a->output = view->get_output();
        a->offset = offset;
        a->tilt_sign = (offset.x != 0) ? ((offset.x > 0) ? 1.0 : -1.0) : 1.0;

        a->transformer = std::make_shared<wf::scene::view_2d_transformer_t>(view);
        view->get_transformed_node()->add_transformer(a->transformer,
            wf::TRANSFORMER_2D, TRANSFORMER_NAME);

        a->progress = wf::animation::simple_animation_t{
            wf::create_option<wf::animation_description_t>(duration)};
        a->progress.animate(0, 1);

        a->on_unmap = [this, view] (wf::view_unmapped_signal*)
        {
            cancel(view, false);
        };
        view->connect(&a->on_unmap);

        anim_t *raw = a.get();
        a->hook = [this, raw] () { step(raw); };
        a->output->render->add_effect(&raw->hook, wf::OUTPUT_EFFECT_PRE);

        anims[view] = std::move(a);
        step(raw);
    }

    void step(anim_t *a)
    {
        const double t = a->progress;
        /* One smooth out-and-back curve: 0 at both ends, 1 at the apex */
        const double s = std::sin(M_PI * std::clamp(t, 0.0, 1.0));

        if (!a->raised && (t >= 0.5))
        {
            wf::view_bring_to_front(a->view);
            a->raised = true;
        }

        auto node = a->view->get_transformed_node();
        node->begin_transform_update();
        a->transformer->translation_x = a->offset.x * s;
        a->transformer->translation_y = a->offset.y * s;
        a->transformer->angle = a->tilt_sign * (double)tilt * (M_PI / 180.0) * s;
        node->end_transform_update();

        if (!a->progress.running())
        {
            /* Finalize outside of the effect hook iteration */
            a->idle_finish.run_once([this, view = a->view] ()
            {
                cancel(view, true);
            });
        }
    }

    void cancel(wayfire_toplevel_view view, bool ensure_raised)
    {
        auto it = anims.find(view);
        if (it == anims.end())
        {
            return;
        }

        auto a = std::move(it->second);
        anims.erase(it);

        a->output->render->rem_effect(&a->hook);
        view->get_transformed_node()->rem_transformer(a->transformer);
        if (ensure_raised && !a->raised && view->is_mapped())
        {
            wf::view_bring_to_front(view);
        }
    }
};
}

DECLARE_WAYFIRE_PLUGIN(shift_switcher::shift_switcher_t);
