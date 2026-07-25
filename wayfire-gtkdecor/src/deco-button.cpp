#include "deco-button.hpp"
#include "deco-theme.hpp"
#include <wayfire/opengl.hpp>
#include <wayfire/plugins/common/cairo-util.hpp>

#define HOVERED  1.0
#define NORMAL   0.0
#define PRESSED -0.7

namespace wf
{
namespace gtkdecor
{
button_t::button_t(const decoration_theme_t& t, std::function<void()> damage) :
    theme(t), damage_callback(damage)
{}

void button_t::set_button_type(button_type_t type)
{
    this->type = type;
    this->hover.animate(0, 0);
    this->texture_valid = false;
    add_idle_damage();
}

button_type_t button_t::get_button_type() const
{
    return this->type;
}

void button_t::set_hover(bool is_hovered)
{
    this->is_hovered = is_hovered;
    if (!this->is_pressed)
    {
        this->hover.animate(is_hovered ? HOVERED : NORMAL);
    }

    add_idle_damage();
}

void button_t::set_pressed(bool is_pressed)
{
    this->is_pressed = is_pressed;
    if (is_pressed)
    {
        this->hover.animate(PRESSED);
    } else
    {
        this->hover.animate(is_hovered ? HOVERED : NORMAL);
    }

    add_idle_damage();
}

void button_t::render(const scene::render_instruction_t& data, wf::geometry_t geometry, bool active)
{
    /* Bake at the resolution we are actually shown at, so that the circle and
     * the symbolic icon stay crisp on HiDPI outputs. */
    update_texture(geometry.width, data.target.scale, active);
    data.pass->add_texture(button_texture.get_texture(), data.target, geometry, data.damage);

    /* running() flips its own state, so it must be called exactly once here */
    if (this->hover.running())
    {
        add_idle_damage();
    }
}

void button_t::update_texture(double size, double scale, bool active)
{
    if (texture_valid && (current_size == size) && (current_scale == scale) &&
        (current_active == active))
    {
        return;
    }

    decoration_theme_t::button_state_t state = {
        .size = size,
        .hover_progress = hover,
        .active = active,
        .scale  = scale,
    };

    auto surface = theme.get_button_surface(type, state);
    this->button_texture = owned_texture_t{surface};
    cairo_surface_destroy(surface);

    current_size   = size;
    current_scale  = scale;
    current_active = active;
    texture_valid  = true;
}

void button_t::add_idle_damage()
{
    this->idle_damage.run_once([=] ()
    {
        this->damage_callback();
        /* The hover animation moved on, the texture has to be baked again */
        this->texture_valid = false;
    });
}

button_t::~button_t()
{}
}
}
