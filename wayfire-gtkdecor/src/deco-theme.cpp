#include "deco-theme.hpp"
#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>
#include <algorithm>
#include <cmath>

namespace wf
{
namespace gtkdecor
{
/** Multipliers applied to the alpha of button_color */
static constexpr double BUTTON_HOVER_BOOST   = 1.8;
static constexpr double BUTTON_PRESSED_BOOST = 2.6;

/** The symbolic icons are drawn on a 16x16 grid, like the SVGs they copy */
static constexpr double ICON_GRID = 16.0;
/** Icon size for the default button size, taken from Adwaita/Yaru */
static constexpr double ICON_FOR_DEFAULT_BUTTON = 16.0 / 22.0;

decoration_theme_t::decoration_theme_t()
{}

int decoration_theme_t::get_title_height() const
{
    return title_height;
}

int decoration_theme_t::get_border_size() const
{
    return border_size;
}

int decoration_theme_t::get_corner_radius() const
{
    return corner_radius;
}

int decoration_theme_t::get_button_size() const
{
    return button_size;
}

int decoration_theme_t::get_button_padding() const
{
    return button_padding;
}

int decoration_theme_t::get_button_spacing() const
{
    return button_spacing;
}

void decoration_theme_t::set_buttons(button_type_t flags)
{
    button_flags = flags;
}

wf::color_t decoration_theme_t::get_background_color(bool active) const
{
    return active ? active_color : inactive_color;
}

wf::color_t decoration_theme_t::get_border_color(bool) const
{
    return border_color;
}

wf::color_t decoration_theme_t::get_highlight_color(bool) const
{
    return highlight_color;
}

wf::color_t decoration_theme_t::get_separator_color(bool) const
{
    return separator_color;
}

wf::color_t decoration_theme_t::get_font_color(bool active) const
{
    return active ? font_color : inactive_font_color;
}

static void set_source(cairo_t *cr, const wf::color_t& color)
{
    cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
}

/**
 * Path of a rectangle whose two top corners are rounded. The bottom side is
 * left square: the client below the title bar has square corners anyway.
 */
static void rounded_top_rect(cairo_t *cr, double x, double y, double w, double h, double r)
{
    r = std::max(0.0, std::min({r, w / 2, h}));
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + r, y + r, r, M_PI, 1.5 * M_PI);
    cairo_arc(cr, x + w - r, y + r, r, 1.5 * M_PI, 2 * M_PI);
    cairo_line_to(cr, x + w, y + h);
    cairo_line_to(cr, x, y + h);
    cairo_close_path(cr);
}

cairo_surface_t*decoration_theme_t::render_corner(int radius, bool right, bool active,
    double scale) const
{
    const int px = std::max(1, (int)std::ceil(radius * scale));
    auto surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, px, px);
    auto cr = cairo_create(surface);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);
    cairo_scale(cr, scale, scale);

    /* Draw the whole 2*radius wide shape and keep only the corner we want */
    if (right)
    {
        cairo_translate(cr, -radius, 0);
    }

    const double b = get_border_size();
    const double w = 2.0 * radius;
    const double h = 2.0 * radius;

    if (b > 0)
    {
        set_source(cr, get_border_color(active));
        rounded_top_rect(cr, 0, 0, w, h, radius);
        cairo_fill(cr);
    }

    cairo_save(cr);
    rounded_top_rect(cr, b, b, w - 2 * b, h - b, radius - b);
    cairo_clip(cr);
    set_source(cr, get_background_color(active));
    cairo_paint(cr);
    set_source(cr, get_highlight_color(active));
    cairo_rectangle(cr, b, b, w - 2 * b, 1);
    cairo_fill(cr);
    cairo_restore(cr);

    cairo_destroy(cr);
    return surface;
}

cairo_surface_t*decoration_theme_t::render_text(std::string text, int width, int height,
    double scale, bool active) const
{
    const auto format = CAIRO_FORMAT_ARGB32;
    auto surface = cairo_image_surface_create(format,
        std::max(1, (int)std::ceil(width * scale)),
        std::max(1, (int)std::ceil(height * scale)));

    if ((height <= 0) || (width <= 0))
    {
        return surface;
    }

    auto cr = cairo_create(surface);
    cairo_scale(cr, scale, scale);

    auto *font_desc = pango_font_description_from_string(((std::string)font).c_str());
    auto *layout    = pango_cairo_create_layout(cr);
    pango_layout_set_font_description(layout, font_desc);
    pango_layout_set_text(layout, text.c_str(), text.size());
    /* Centre the title in the window, like a GTK header bar does, and cut it
     * short instead of letting it run under the buttons */
    pango_layout_set_width(layout, width * PANGO_SCALE);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);
    pango_cairo_update_layout(cr, layout);

    int text_w, text_h;
    pango_layout_get_pixel_size(layout, &text_w, &text_h);

    set_source(cr, get_font_color(active));
    cairo_move_to(cr, 0, (height - text_h) / 2.0);
    pango_cairo_show_layout(cr, layout);

    pango_font_description_free(font_desc);
    g_object_unref(layout);
    cairo_destroy(cr);

    return surface;
}

/** window-close-symbolic, traced from the Yaru/Adwaita SVG (16x16 grid) */
static void icon_close(cairo_t *cr)
{
    cairo_move_to(cr, 4.795, 3.912);
    cairo_line_to(cr, 3.912, 4.795);
    cairo_line_to(cr, 4.059, 4.941);
    cairo_line_to(cr, 7.117, 8.000);
    cairo_line_to(cr, 4.060, 11.059);
    cairo_line_to(cr, 3.913, 11.205);
    cairo_line_to(cr, 4.796, 12.088);
    cairo_line_to(cr, 4.942, 11.941);
    cairo_line_to(cr, 8.000, 8.883);
    cairo_line_to(cr, 11.059, 11.941);
    cairo_line_to(cr, 11.205, 12.088);
    cairo_line_to(cr, 12.088, 11.205);
    cairo_line_to(cr, 11.941, 11.059);
    cairo_line_to(cr, 8.883, 8.000);
    cairo_line_to(cr, 11.941, 4.941);
    cairo_line_to(cr, 12.088, 4.795);
    cairo_line_to(cr, 11.205, 3.912);
    cairo_line_to(cr, 11.059, 4.059);
    cairo_line_to(cr, 8.000, 7.117);
    cairo_line_to(cr, 4.941, 4.060);
    cairo_close_path(cr);
    cairo_fill(cr);
}

/** window-maximize-symbolic: a one pixel square outline */
static void icon_maximize(cairo_t *cr)
{
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD);
    cairo_rectangle(cr, 4, 4, 8, 8);
    cairo_rectangle(cr, 5, 5, 6, 6);
    cairo_fill(cr);
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING);
}

/** window-minimize-symbolic: a bar near the bottom */
static void icon_minimize(cairo_t *cr)
{
    cairo_rectangle(cr, 4, 10, 8, 1);
    cairo_fill(cr);
}

cairo_surface_t*decoration_theme_t::get_button_surface(button_type_t button,
    const button_state_t& state) const
{
    const int px = std::max(1, (int)std::ceil(state.size * state.scale));
    cairo_surface_t *button_surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, px, px);

    auto cr = cairo_create(button_surface);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);
    cairo_scale(cr, state.scale, state.scale);

    /* Flat circular background, like a GTK title button. It gets darker on
     * hover and darker still while pressed. */
    wf::color_t base = button_color;
    if (state.hover_progress > 0)
    {
        base.a *= 1.0 + state.hover_progress * (BUTTON_HOVER_BOOST - 1.0);
    } else if (state.hover_progress < 0)
    {
        base.a *= 1.0 + (-state.hover_progress) * (BUTTON_PRESSED_BOOST - 1.0);
    }

    base.a = std::min(1.0, base.a);
    set_source(cr, base);
    cairo_arc(cr, state.size / 2, state.size / 2, state.size / 2, 0, 2 * M_PI);
    cairo_fill(cr);

    /* Symbolic icon on top */
    const double icon = state.size * ICON_FOR_DEFAULT_BUTTON;
    cairo_translate(cr, (state.size - icon) / 2, (state.size - icon) / 2);
    cairo_scale(cr, icon / ICON_GRID, icon / ICON_GRID);
    set_source(cr, get_font_color(state.active));

    switch (button)
    {
      case BUTTON_CLOSE:
        icon_close(cr);
        break;

      case BUTTON_TOGGLE_MAXIMIZE:
        icon_maximize(cr);
        break;

      case BUTTON_MINIMIZE:
        icon_minimize(cr);
        break;

      default:
        break;
    }

    cairo_destroy(cr);

    return button_surface;
}
}
}
