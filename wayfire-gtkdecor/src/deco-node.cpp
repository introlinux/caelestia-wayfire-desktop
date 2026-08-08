#include "wayfire/geometry.hpp"
#include "wayfire/scene-input.hpp"
#include "wayfire/scene-operations.hpp"
#include "wayfire/scene-render.hpp"
#include "wayfire/scene.hpp"
#include "wayfire/signal-provider.hpp"
#include "wayfire/toplevel.hpp"
#include <algorithm>
#include <memory>

#include <linux/input-event-codes.h>

#include <wayfire/nonstd/wlroots.hpp>
#include <wayfire/output.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/core.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/plugins/common/cairo-util.hpp>

#include "deco-node.hpp"
#include "deco-layout.hpp"
#include "deco-theme.hpp"

#include <cairo.h>

/* Wayfire has no union of two boxes, and its operator& on them answers whether
 * they intersect rather than giving back the overlap. */
static wf::geometry_t box_union(const wf::geometry_t& a, const wf::geometry_t& b)
{
    const int x1 = std::min(a.x, b.x);
    const int y1 = std::min(a.y, b.y);
    const int x2 = std::max(a.x + a.width, b.x + b.width);
    const int y2 = std::max(a.y + a.height, b.y + b.height);
    return {x1, y1, x2 - x1, y2 - y1};
}

/**
 * The scene node which paints the frame around a window. The look it goes for
 * is that of a GTK client-side header bar: rounded top corners, a hairline
 * border with a lighter line just inside it, the title centred in bold and a
 * flat circular button on the right.
 */
class gtk_decoration_node_t : public wf::scene::node_t, public wf::pointer_interaction_t,
    public wf::touch_interaction_t
{
    std::weak_ptr<wf::toplevel_view_interface_t> _view;
    wf::signal::connection_t<wf::view_title_changed_signal> title_set =
        [=] (wf::view_title_changed_signal *ev)
    {
        if (auto view = _view.lock())
        {
            view->damage();
        }
    };

    struct
    {
        wf::owned_texture_t tex;
        std::string current_text = "";
        wf::dimensions_t size    = {0, 0};
        bool active = false;
    } title_texture;

    struct
    {
        wf::owned_texture_t left;
        wf::owned_texture_t right;
        int radius    = -1;
        double scale  = 0;
        bool active   = false;
        bool baked    = false;
    } corners;

    /* Nine slices of a drop shadow. The atlas only depends on the corner
     * radius, the shadow size and the colour, never on the size of the window,
     * so it survives a resize untouched. */
    struct
    {
        wf::owned_texture_t tex;
        int radius    = -1;
        int size      = -1;
        double scale  = 0;
        bool active   = false;
        bool baked    = false;
    } shadow;

    void update_title(int width, int height, double scale, bool active)
    {
        auto view = _view.lock();
        if (!view)
        {
            return;
        }

        wf::dimensions_t target_size = {
            static_cast<int32_t>(width * scale),
            static_cast<int32_t>(height * scale)
        };

        if ((title_texture.size != target_size) ||
            (title_texture.current_text != view->get_title()) ||
            (title_texture.active != active))
        {
            auto surface = theme.render_text(view->get_title(), width, height, scale, active);
            title_texture.tex = wf::owned_texture_t{surface};
            cairo_surface_destroy(surface);
            title_texture.current_text = view->get_title();
            title_texture.size   = target_size;
            title_texture.active = active;
        }
    }

    void update_corners(int radius, double scale, bool active)
    {
        if (corners.baked && (corners.radius == radius) && (corners.scale == scale) &&
            (corners.active == active))
        {
            return;
        }

        auto left = theme.render_corner(radius, false, active, scale);
        corners.left = wf::owned_texture_t{left};
        cairo_surface_destroy(left);

        auto right = theme.render_corner(radius, true, active, scale);
        corners.right = wf::owned_texture_t{right};
        cairo_surface_destroy(right);

        corners.radius = radius;
        corners.scale  = scale;
        corners.active = active;
        corners.baked  = true;
    }

    void update_shadow(int radius, int size, double scale, bool active)
    {
        if (shadow.baked && (shadow.radius == radius) && (shadow.size == size) &&
            (shadow.scale == scale) && (shadow.active == active))
        {
            return;
        }

        auto surface = theme.render_shadow_atlas(radius, size, active, scale);
        shadow.tex = wf::owned_texture_t{surface};
        cairo_surface_destroy(surface);

        shadow.radius = radius;
        shadow.size   = size;
        shadow.scale  = scale;
        shadow.active = active;
        shadow.baked  = true;
    }

    /** The radius the frame rounds its two top corners with, as render() uses it */
    int get_frame_corner_radius() const
    {
        if (current_titlebar <= 0)
        {
            return 0;
        }

        /* The upper bound is floored at 0 on purpose: std::clamp asserts when
         * hi < lo, and an assert here aborts the whole compositor. A degenerate
         * size must round no corners, not take the session down. */
        return std::clamp(theme.get_corner_radius(), 0,
            std::max(0, std::min(size.width / 2, current_titlebar)));
    }

    /**
     * What the user actually sees of the window, and so what casts the shadow:
     * the frame inset by its border. With a transparent border, which is how it
     * doubles as an invisible margin to grab when resizing, the border is not
     * part of the silhouette at all. An opaque one simply hides the innermost
     * band of the shadow, which is no worse than not casting it from there.
     */
    wf::geometry_t get_silhouette_box() const
    {
        const int b = current_thickness;
        return {b, b, size.width - 2 * b, size.height - 2 * b};
    }

    bool has_shadow() const
    {
        if ((theme.get_shadow_size() <= 0) || (current_titlebar <= 0))
        {
            return false;
        }

        auto view = _view.lock();
        if (!view)
        {
            return false;
        }

        /* Nothing casts a shadow when it is flush against the screen or against
         * its neighbours, which is what GTK does with its own windows too. */
        const auto& state = view->toplevel()->current();
        return !state.fullscreen && !state.tiled_edges;
    }

    /**
     * Where the nine slices land, frame-local. The three columns and rows are
     * given as four coordinates each, so a cell is simply [x[i], x[i + 1]].
     */
    struct shadow_grid_t
    {
        int x[4], y[4];
        /* Slice actually drawn, and the one the atlas was cut at. They differ
         * on windows too small to fit two full slices. */
        int drawn = 0;
        int baked = 0;
        int atlas = 0;
        bool valid = false;
    };

    shadow_grid_t get_shadow_grid() const
    {
        shadow_grid_t g;
        if (!has_shadow())
        {
            return g;
        }

        const int s   = theme.get_shadow_size();
        const int off = theme.get_shadow_offset();
        const auto si = get_silhouette_box();
        /* The shadow reaches `s` out of the silhouette and is pushed down by
         * `off`, as if the light came from above. */
        const wf::geometry_t sb{
            si.x - s, si.y - s + off, si.width + 2 * s, si.height + 2 * s
        };

        const int radius = std::max(0, get_frame_corner_radius() - current_thickness);
        g.baked = wf::gtkdecor::decoration_theme_t::get_shadow_slice(radius, s);
        g.atlas = wf::gtkdecor::decoration_theme_t::get_shadow_atlas_size(radius, s);
        /* A window can be narrower or shorter than two slices. Cropping them
         * from the outside keeps the falloff where it is actually seen. */
        g.drawn = std::max(1, std::min({g.baked, sb.width / 2, sb.height / 2}));

        g.x[0] = sb.x;
        g.x[1] = sb.x + g.drawn;
        g.x[2] = sb.x + sb.width - g.drawn;
        g.x[3] = sb.x + sb.width;
        g.y[0] = sb.y;
        g.y[1] = sb.y + g.drawn;
        g.y[2] = sb.y + sb.height - g.drawn;
        g.y[3] = sb.y + sb.height;
        g.valid = true;
        return g;
    }

    /**
     * Walk the eight slices that are drawn, middle one excluded: it would fall
     * under the window, where nothing of it could be seen.
     */
    template<class F>
    void for_each_shadow_slice(const shadow_grid_t& g, F&& fn) const
    {
        for (int j = 0; j < 3; j++)
        {
            for (int i = 0; i < 3; i++)
            {
                if ((i == 1) && (j == 1))
                {
                    continue;
                }

                const wf::geometry_t dst{
                    g.x[i], g.y[j], g.x[i + 1] - g.x[i], g.y[j + 1] - g.y[j]
                };
                if ((dst.width > 0) && (dst.height > 0))
                {
                    fn(i, j, dst);
                }
            }
        }
    }

    void render_shadow(const wf::scene::render_instruction_t& data, bool active)
    {
        const auto g = get_shadow_grid();
        if (!g.valid)
        {
            return;
        }

        update_shadow(std::max(0, get_frame_corner_radius() - current_thickness),
            theme.get_shadow_size(), data.target.scale, active);

        const double sc   = data.target.scale;
        const auto origin = get_offset();
        /* Atlas columns, in its own logical units. The middle one is a single
         * pixel of the straight side, stretched along the window. */
        const double src_pos[3] = {0.0, (double)g.baked, (double)(g.atlas - g.drawn)};
        const double src_len[3] = {(double)g.drawn, 1.0, (double)g.drawn};

        for_each_shadow_slice(g, [&] (int i, int j, wf::geometry_t dst)
        {
            auto tex = shadow.tex.get_texture();
            tex.source_box = wlr_fbox{
                src_pos[i] * sc, src_pos[j] * sc, src_len[i] * sc, src_len[j] * sc
            };
            data.pass->add_texture(tex, data.target, dst + origin, data.damage);
        });
    }

  public:
    wf::gtkdecor::decoration_theme_t theme;
    wf::gtkdecor::decoration_layout_t layout;
    /* The interactive part of the frame: title bar, buttons and the four resize
     * edges. It decides what swallows pointer and touch events. */
    wf::region_t input_region;
    /* The part the frame paints, used to clip the render pass. It matches
     * input_region today, but the two answer different questions: a frame may
     * well paint where it does not want to be clicked, a drop shadow being the
     * obvious case. */
    wf::region_t render_region;

    /* Initialised here and not just in resize(): the constructor already reads
     * them through update_decoration_size() -> recalculate_regions(), which is
     * long before gtk_decorator_t gets to call resize(). */
    wf::dimensions_t size = {0, 0};

    int current_thickness = 0;
    int current_titlebar  = 0;

    gtk_decoration_node_t(wayfire_toplevel_view view) :
        node_t(false),
        theme{},
        layout{theme, [=] (wlr_box box) { wf::scene::damage_node(shared_from_this(), box + get_offset()); }}
    {
        this->_view = view->weak_from_this();
        view->connect(&title_set);
        if (view->parent)
        {
            theme.set_buttons(wf::gtkdecor::button_type_t(wf::gtkdecor::BUTTON_TOGGLE_MAXIMIZE |
                wf::gtkdecor::BUTTON_CLOSE));
        } else
        {
            theme.set_buttons(wf::gtkdecor::button_type_t(wf::gtkdecor::BUTTON_MINIMIZE |
                wf::gtkdecor::BUTTON_TOGGLE_MAXIMIZE | wf::gtkdecor::BUTTON_CLOSE));
        }

        // make sure to hide frame if the view is fullscreen
        update_decoration_size();
    }

    wf::point_t get_offset()
    {
        return {-current_thickness, -current_titlebar};
    }

    void render(const wf::scene::render_instruction_t& data)
    {
        const auto origin = get_offset();
        const int W = size.width;
        const int H = size.height;
        const int b = current_thickness;
        const int T = current_titlebar;

        if ((W <= 0) || (H <= 0))
        {
            return;
        }

        bool active = false;
        if (auto view = _view.lock())
        {
            active = view->activated;
        }

        const auto bg  = theme.get_background_color(active);
        const auto bd  = theme.get_border_color(active);
        const auto hl  = theme.get_highlight_color(active);
        const auto sep = theme.get_separator_color(active);

        /* All the pieces below are in frame-local coordinates: (0, 0) is the
         * top left corner of the frame, not of the client. */
        auto rect = [&] (wf::geometry_t g, const wf::color_t& color)
        {
            if ((g.width > 0) && (g.height > 0))
            {
                /* add_rect() blends with premultiplied alpha, but the colors come
                 * straight from the config, so they have to be premultiplied here.
                 * The cairo pieces need no such thing: cairo does it on its own. */
                const wf::color_t premultiplied{
                    color.r * color.a, color.g * color.a, color.b * color.a, color.a};
                data.pass->add_rect(premultiplied, data.target, g + origin, data.damage);
            }
        };

        /* Behind everything else: the frame paints over it, and its own
         * transparent parts leave it be. */
        render_shadow(data, active);

        int radius = 0;
        if (T > 0)
        {
            radius = get_frame_corner_radius();
            if (radius > 0)
            {
                update_corners(radius, data.target.scale, active);
                data.pass->add_texture(corners.left.get_texture(), data.target,
                    wf::geometry_t{0, 0, radius, radius} + origin, data.damage);
                data.pass->add_texture(corners.right.get_texture(), data.target,
                    wf::geometry_t{W - radius, 0, radius, radius} + origin, data.damage);
            }

            /* Top border, then the band left over between the two corners, and
             * the light line painted just inside the border. The background
             * starts right below the border and the line goes on top of it,
             * exactly like render_corner() stacks them, so that the straight
             * part and the corners line up whatever the colors are. */
            rect({radius, 0, W - 2 * radius, b}, bd);
            rect({radius, b, W - 2 * radius, radius - b}, bg);
            rect({radius, b, W - 2 * radius, 1}, hl);
            /* Title bar background across the full width below the corners */
            rect({b, radius, W - 2 * b, T - 1 - radius}, bg);
            /* The line separating the title bar from the client */
            rect({b, T - 1, W - 2 * b, 1}, sep);
        } else
        {
            rect({0, 0, W, b}, bd);
        }

        /* Side and bottom borders. Everything between them is covered by the
         * client, so it is not worth painting. */
        rect({0, radius, b, H - radius - b}, bd);
        rect({W - b, radius, b, H - radius - b}, bd);
        rect({0, H - b, W, b}, bd);

        /* Title and buttons */
        for (auto item : layout.get_renderable_areas())
        {
            if (item->get_type() == wf::gtkdecor::DECORATION_AREA_TITLE)
            {
                const int reserved = layout.get_reserved_width();
                wf::geometry_t title_geometry = {reserved, 0, W - 2 * reserved, T};
                if (title_geometry.width <= 0)
                {
                    continue;
                }

                update_title(title_geometry.width, title_geometry.height, data.target.scale, active);
                if (title_texture.tex.get_texture().texture != NULL)
                {
                    data.pass->add_texture(title_texture.tex.get_texture(), data.target,
                        title_geometry + origin, data.damage);
                }
            } else // button
            {
                item->as_button().render(data, item->get_geometry() + origin, active);
            }
        }
    }

    std::optional<wf::scene::input_node_t> find_node_at(const wf::pointf_t& at) override
    {
        if (auto view = _view.lock())
        {
            wf::pointf_t local = at - wf::pointf_t{get_offset()};
            if (input_region.contains_pointf(local) && view->is_mapped())
            {
                return wf::scene::input_node_t{
                    .node = this,
                    .local_coords = local,
                };
            }
        }

        return {};
    }

    pointer_interaction_t& pointer_interaction() override
    {
        return *this;
    }

    touch_interaction_t& touch_interaction() override
    {
        return *this;
    }

    class decoration_render_instance_t : public wf::scene::render_instance_t
    {
        std::shared_ptr<gtk_decoration_node_t> self;
        wf::scene::damage_callback push_damage;

        wf::signal::connection_t<wf::scene::node_damage_signal> on_surface_damage =
            [=] (wf::scene::node_damage_signal *data)
        {
            push_damage(data->region);
        };

      public:
        decoration_render_instance_t(gtk_decoration_node_t *self, wf::scene::damage_callback push_damage)
        {
            this->self = std::dynamic_pointer_cast<gtk_decoration_node_t>(self->shared_from_this());
            this->push_damage = push_damage;
            self->connect(&on_surface_damage);
        }

        void schedule_instructions(std::vector<wf::scene::render_instruction_t>& instructions,
            const wf::render_target_t& target, wf::region_t& damage) override
        {
            auto our_region = self->render_region + self->get_offset();
            wf::region_t our_damage = damage & our_region;
            if (!our_damage.empty())
            {
                instructions.push_back(wf::scene::render_instruction_t{
                    .instance = this,
                    .target   = target,
                    .damage   = std::move(our_damage),
                });
            }
        }

        void render(const wf::scene::render_instruction_t& data) override
        {
            self->render(data);
        }
    };

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *output = nullptr) override
    {
        instances.push_back(std::make_unique<decoration_render_instance_t>(this, push_damage));
    }

    wf::geometry_t get_bounding_box() override
    {
        auto box = wf::construct_box(get_offset(), size);

        /* The shadow is painted outside the frame, so it has to be part of the
         * box or it would never be damaged, and so never repainted. Nothing in
         * the scene graph clips a view to its geometry: an inner node reports
         * the union of its children and passes damage straight down. */
        const auto g = get_shadow_grid();
        if (g.valid)
        {
            const auto origin = get_offset();
            for_each_shadow_slice(g, [&] (int, int, wf::geometry_t dst)
            {
                box = box_union(box, dst + origin);
            });
        }

        return box;
    }

    /* wf::compositor_surface_t implementation */
    void handle_pointer_enter(wf::pointf_t point) override
    {
        point -= wf::pointf_t{get_offset()};
        layout.handle_motion(point.x, point.y);
    }

    void handle_pointer_leave() override
    {
        layout.handle_focus_lost();
    }

    void handle_pointer_motion(wf::pointf_t to, uint32_t) override
    {
        to -= wf::pointf_t{get_offset()};
        handle_action(layout.handle_motion(to.x, to.y));
    }

    void handle_pointer_button(const wlr_pointer_button_event& ev) override
    {
        if (ev.button != BTN_LEFT)
        {
            return;
        }

        handle_action(layout.handle_press_event(ev.state == WL_POINTER_BUTTON_STATE_PRESSED));
    }

    void handle_action(wf::gtkdecor::decoration_layout_t::action_response_t action)
    {
        if (auto view = _view.lock())
        {
            switch (action.action)
            {
              case wf::gtkdecor::DECORATION_ACTION_MOVE:
                return wf::get_core().default_wm->move_request(view);

              case wf::gtkdecor::DECORATION_ACTION_RESIZE:
                return wf::get_core().default_wm->resize_request(view, action.edges);

              case wf::gtkdecor::DECORATION_ACTION_CLOSE:
                return view->close();

              case wf::gtkdecor::DECORATION_ACTION_TOGGLE_MAXIMIZE:
                if (view->pending_tiled_edges())
                {
                    return wf::get_core().default_wm->tile_request(view, 0);
                } else
                {
                    return wf::get_core().default_wm->tile_request(view, wf::TILED_EDGES_ALL);
                }

                break;

              case wf::gtkdecor::DECORATION_ACTION_MINIMIZE:
                return wf::get_core().default_wm->minimize_request(view, true);
                break;

              default:
                break;
            }
        }
    }

    void handle_touch_down(uint32_t time_ms, int finger_id, wf::pointf_t position) override
    {
        handle_touch_motion(time_ms, finger_id, position);
        handle_action(layout.handle_press_event());
    }

    void handle_touch_up(uint32_t time_ms, int finger_id, wf::pointf_t lift_off_position) override
    {
        handle_action(layout.handle_press_event(false));
        layout.handle_focus_lost();
    }

    void handle_touch_motion(uint32_t time_ms, int finger_id, wf::pointf_t position) override
    {
        position -= wf::pointf_t{get_offset()};
        handle_action(layout.handle_motion(position.x, position.y));
    }

    /* Both regions are recomputed together so that they cannot drift apart. */
    void recalculate_regions()
    {
        input_region  = layout.calculate_region();
        render_region = input_region;

        /* Here is where the two part ways: the shadow is painted, so it joins
         * the render region, but it stays out of the input one on purpose. A
         * band that swallowed clicks would make it impossible to reach
         * anything sitting just behind a window. */
        const auto g = get_shadow_grid();
        if (g.valid)
        {
            for_each_shadow_slice(g, [&] (int, int, wf::geometry_t dst)
            {
                render_region |= dst;
            });
        }
    }

    void clear_regions()
    {
        input_region.clear();
        render_region.clear();
    }

    void resize(wf::dimensions_t dims)
    {
        if (auto view = _view.lock())
        {
            view->damage();
            size = dims;
            layout.resize(size.width, size.height);
            if (!view->toplevel()->current().fullscreen)
            {
                this->recalculate_regions();
            }

            view->damage();
        }
    }

    void update_decoration_size()
    {
        bool fullscreen = _view.lock()->toplevel()->current().fullscreen;
        if (fullscreen)
        {
            current_thickness = 0;
            current_titlebar  = 0;
            this->clear_regions();
        } else
        {
            current_thickness = theme.get_border_size();
            current_titlebar  = theme.get_title_height() + theme.get_border_size();
            this->recalculate_regions();
        }
    }
};

wf::gtk_decorator_t::gtk_decorator_t(wayfire_toplevel_view view)
{
    this->view = view;
    deco = std::make_shared<gtk_decoration_node_t>(view);
    deco->resize(wf::dimensions(view->get_pending_geometry()));
    wf::scene::add_back(view->get_surface_root_node(), deco);

    view->connect(&on_view_activated);
    view->connect(&on_view_geometry_changed);
    view->connect(&on_view_fullscreen);

    on_view_activated = [this] (auto)
    {
        wf::scene::damage_node(deco, deco->get_bounding_box());
    };

    on_view_geometry_changed = [this] (auto)
    {
        deco->resize(wf::dimensions(this->view->get_geometry()));
    };

    on_view_fullscreen = [this] (auto)
    {
        deco->update_decoration_size();
        if (!this->view->toplevel()->current().fullscreen)
        {
            deco->resize(wf::dimensions(this->view->get_geometry()));
        }
    };
}

wf::gtk_decorator_t::~gtk_decorator_t()
{
    wf::scene::remove_child(deco);
}

wf::decoration_margins_t wf::gtk_decorator_t::get_margins(const wf::toplevel_state_t& state)
{
    if (state.fullscreen)
    {
        return {0, 0, 0, 0};
    }

    const int thickness = deco->theme.get_border_size();
    const int titlebar  = deco->theme.get_title_height() + deco->theme.get_border_size();
    return wf::decoration_margins_t{
        .left   = thickness,
        .right  = thickness,
        .bottom = thickness,
        .top    = titlebar,
    };
}
