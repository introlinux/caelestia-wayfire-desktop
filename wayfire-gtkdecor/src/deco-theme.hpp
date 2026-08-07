#pragma once
#include <wayfire/render-manager.hpp>
#include <wayfire/scene-render.hpp>
#include "deco-button.hpp"

namespace wf
{
namespace gtkdecor
{
/**
 * Determines the colours, sizes and the actual cairo painting of the
 * decorations. Everything here is expressed in logical pixels; surfaces are
 * baked at `scale` times that size.
 */
class decoration_theme_t
{
  public:
    decoration_theme_t();

    /** @return The height of the title bar, without the top border */
    int get_title_height() const;
    /** @return The border used for resizing */
    int get_border_size() const;
    /** @return The radius of the two top corners */
    int get_corner_radius() const;
    /** @return The diameter of a titlebar button */
    int get_button_size() const;
    /** @return The gap between the buttons and the window edge */
    int get_button_padding() const;
    /** @return The gap between two adjacent buttons */
    int get_button_spacing() const;
    /** @return How far the drop shadow reaches out, 0 when it is disabled */
    int get_shadow_size() const;
    /** @return How far down the drop shadow is pushed, as light from above */
    int get_shadow_offset() const;

    /** Set the flags for buttons */
    void set_buttons(button_type_t flags);
    button_type_t button_flags;

    wf::color_t get_background_color(bool active) const;
    wf::color_t get_border_color(bool active) const;
    wf::color_t get_highlight_color(bool active) const;
    wf::color_t get_separator_color(bool active) const;
    wf::color_t get_font_color(bool active) const;
    wf::color_t get_shadow_color(bool active) const;

    /**
     * Bake one of the two rounded top corners, border and highlight included.
     * The result is a radius x radius image (times scale); everything outside
     * the rounded shape is transparent.
     *
     * The caller is responsible for freeing the memory afterwards.
     */
    cairo_surface_t *render_corner(int radius, bool right, bool active, double scale) const;

    /**
     * Bake the drop shadow of a rounded top rect into a square atlas meant to
     * be drawn as nine slices, so that one small image serves every window
     * size and nothing has to be baked again while a window is resized.
     *
     * @param radius Radius of the two top corners of the shape casting the
     *   shadow. The bottom ones are square, as they are on the window itself.
     * @param size How far the shadow reaches out of the shape.
     *
     * The shape sits @size away from every edge, so the blur just reaches the
     * border of the atlas. The slice size the caller must cut at is given by
     * get_shadow_slice(): the middle row and column are only uniform, and so
     * only safe to stretch, beyond the reach of the blurred corners.
     *
     * The caller is responsible for freeing the memory afterwards.
     */
    cairo_surface_t *render_shadow_atlas(int radius, int size, bool active, double scale) const;

    /** @return The slice size of the atlas baked for these parameters */
    static int get_shadow_slice(int radius, int size);
    /** @return The side of the square atlas baked for these parameters */
    static int get_shadow_atlas_size(int radius, int size);

    /**
     * Render the title, centred inside a width x height box and ellipsized if
     * it does not fit.
     *
     * The caller is responsible for freeing the memory afterwards.
     */
    cairo_surface_t *render_text(std::string text, int width, int height, double scale,
        bool active) const;

    struct button_state_t
    {
        /** Button diameter, in logical pixels */
        double size;
        /** Progress of button hover, in range [-1, 1].
         * Negative numbers are usually used for pressed state. */
        double hover_progress;
        /** Whether the window owning the button is focused */
        bool active;
        /** Output scale the button will be rendered at */
        double scale;
    };

    /**
     * Get the icon for the given button.
     * The caller is responsible for freeing the memory afterwards.
     */
    cairo_surface_t *get_button_surface(button_type_t button,
        const button_state_t& state) const;

  private:
    wf::option_wrapper_t<std::string> font{"gtkdecor/font"};
    wf::option_wrapper_t<int> title_height{"gtkdecor/title_height"};
    wf::option_wrapper_t<int> border_size{"gtkdecor/border_size"};
    wf::option_wrapper_t<int> corner_radius{"gtkdecor/corner_radius"};
    wf::option_wrapper_t<int> button_size{"gtkdecor/button_size"};
    wf::option_wrapper_t<int> button_padding{"gtkdecor/button_padding"};
    wf::option_wrapper_t<int> button_spacing{"gtkdecor/button_spacing"};
    wf::option_wrapper_t<int> shadow_size{"gtkdecor/shadow_size"};
    wf::option_wrapper_t<int> shadow_offset{"gtkdecor/shadow_offset"};

    wf::option_wrapper_t<wf::color_t> active_color{"gtkdecor/active_color"};
    wf::option_wrapper_t<wf::color_t> inactive_color{"gtkdecor/inactive_color"};
    wf::option_wrapper_t<wf::color_t> border_color{"gtkdecor/border_color"};
    wf::option_wrapper_t<wf::color_t> highlight_color{"gtkdecor/highlight_color"};
    wf::option_wrapper_t<wf::color_t> separator_color{"gtkdecor/separator_color"};
    wf::option_wrapper_t<wf::color_t> font_color{"gtkdecor/font_color"};
    wf::option_wrapper_t<wf::color_t> inactive_font_color{"gtkdecor/inactive_font_color"};
    wf::option_wrapper_t<wf::color_t> button_color{"gtkdecor/button_color"};
    wf::option_wrapper_t<wf::color_t> shadow_color{"gtkdecor/shadow_color"};
    wf::option_wrapper_t<wf::color_t> inactive_shadow_color{"gtkdecor/inactive_shadow_color"};
};
}
}
