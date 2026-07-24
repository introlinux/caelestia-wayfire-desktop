/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2026 caelestia-wayfire
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <cmath>
#include <ctime>
#include <cstdlib>
#include <string>
#include <vector>

#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/option-wrapper.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <wayfire/plugins/animate/animate.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>

// --- Shaders --------------------------------------------------------------

// Piece shader: samples the window texture and discards fragments outside the
// current strip's band, so the window is sliced without any geometry work.
static const char *piece_vert_source =
    R"(
#version 100

attribute highp vec2 position;
attribute highp vec2 uv_in;

uniform mat4 matrix;

varying highp vec2 uv;

void main() {
    uv = uv_in;
    gl_Position = matrix * vec4(position, 0.0, 1.0);
}
)";

static const char *piece_frag_source =
    R"(
#version 100
@builtin_ext@
@builtin@

precision highp float;

varying highp vec2 uv;

uniform highp vec2 winsize;    // (window_w, window_h) in px
uniform highp vec2 cutnA;      // primary cut normal scaled by (window_w, window_h)
uniform highp vec2 bandA;      // [lo, hi] of this piece along cutnA, in screen px
uniform highp vec2 cutnB;      // secondary cut normal (for cross/x patterns)
uniform highp vec2 bandB;      // [lo, hi] along cutnB
uniform highp float useB;      // >0.5 to enable the second cut
uniform highp float curvedA;   // >0.5 => cut A is an arc, not a straight line
uniform highp vec2 centerA;    // arc centre, px relative to the window centre
uniform highp float radiusA;   // arc radius, px
uniform highp float curvedB;
uniform highp vec2 centerB;
uniform highp float radiusB;
uniform highp vec2 edgemaskA;  // 1.0 where a bandA boundary is an interior cut line
uniform highp vec2 edgemaskB;  // 1.0 where a bandB boundary is an interior cut line
uniform highp float alpha;     // per-piece fade
uniform highp float edge;      // strength of the bright "cut paper" edge

// Signed distance to the cut, in screen pixels. A straight cut is the distance
// to a line; a curved one is the distance to a circle, so that concentric radii
// give parallel arcs. Both keep the same sign convention.
float cut_dist(vec2 tc, vec2 cutn, float curved, vec2 c, float r)
{
    if (curved > 0.5)
    {
        vec2 P = (tc - vec2(0.5)) * winsize;
        return length(P - c) - r;
    }

    return dot(tc - vec2(0.5), cutn);
}

void main()
{
    float sA = cut_dist(uv, cutnA, curvedA, centerA, radiusA);
    if (sA < bandA.x || sA >= bandA.y)
    {
        discard;
    }

    float d = 1.0e6;
    d = min(d, mix(1.0e6, sA - bandA.x, edgemaskA.x));
    d = min(d, mix(1.0e6, bandA.y - sA, edgemaskA.y));

    if (useB > 0.5)
    {
        float sB = cut_dist(uv, cutnB, curvedB, centerB, radiusB);
        if (sB < bandB.x || sB >= bandB.y)
        {
            discard;
        }

        d = min(d, mix(1.0e6, sB - bandB.x, edgemaskB.x));
        d = min(d, mix(1.0e6, bandB.y - sB, edgemaskB.y));
    }

    // The snapshot lives in an auxilliary buffer, whose origin is bottom-left, so
    // the texel lookup is mirrored vertically. Flip only the sampling coordinate:
    // `uv` itself must stay as-is because cut_dist() derives the cut geometry from
    // it, and flipping that would mirror the strokes and arcs.
    vec4 col = get_pixel(vec2(uv.x, 1.0 - uv.y)) * alpha;
    float e  = (1.0 - smoothstep(0.0, 5.0, d)) * edge;
    col.rgb += e * 0.5 * alpha;

    gl_FragColor = col;
}
)";

// Blade shader: a solid additive glow drawn along the cut line.
static const char *blade_vert_source =
    R"(
#version 100

attribute highp vec2 position;
attribute highp vec2 coord;   // (along 0..1, across -1..1)

uniform mat4 matrix;

varying highp vec2 v_coord;

void main() {
    v_coord = coord;
    gl_Position = matrix * vec4(position, 0.0, 1.0);
}
)";

static const char *blade_frag_source =
    R"(
#version 100

precision highp float;

varying highp vec2 v_coord;

uniform highp vec4 color;      // rgb + brightness in .a
uniform highp float glint_pos; // 0..1 sweep head position
uniform highp float flash;     // overall blade intensity / fade
uniform highp float mode;      // 0 = additive glow pass, 1 = solid core pass

void main()
{
    float across = v_coord.y;
    float along  = v_coord.x;

    // the blade "draws" the cut: a bright tip travels along the line, leaving a
    // trail behind it that is brightest near the tip.
    float head   = glint_pos;
    float tip    = exp(-pow((along - head) / 0.05, 2.0));
    float body   = step(along, head);
    float trail  = body * (0.15 + 0.85 * smoothstep(head - 0.7, head, along));
    float reveal = max(tip * 1.4, trail);

    if (mode < 0.5)
    {
        // wide soft glow, additive: reads on dark backgrounds
        float halo = smoothstep(1.0, 0.0, abs(across));
        float g = clamp(halo * reveal * flash * color.a, 0.0, 1.0);
        gl_FragColor = vec4(color.rgb, g);
    }
    else
    {
        // thin opaque core, normal blend: reads on ANY background
        float core = smoothstep(0.35, 0.0, abs(across));
        float a = clamp(core * reveal * flash, 0.0, 1.0);
        gl_FragColor = vec4(color.rgb * a, a);
    }
}
)";

namespace wf
{
namespace ninjaslash
{
using namespace wf::scene;
using namespace wf::animate;
using namespace wf::animation;

static std::string ninjaslash_transformer_name = "animation-ninjaslash";

wf::option_wrapper_t<wf::animation_description_t> ninjaslash_duration{"ninjaslash/duration"};

static float smoothstep01(float edge0, float edge1, float x)
{
    float t = std::clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

class ninjaslash_transformer : public wf::scene::view_2d_transformer_t
{
  public:
    wayfire_view view;
    wf::output_t *output = nullptr;
    wf::geometry_t animation_geometry;
    duration_t progression{ninjaslash_duration};

    // Our own snapshot of the window, taken once at construction. Rendering every
    // frame from this fixed texture (instead of get_texture(), which recomposites
    // the view's children) keeps the orientation consistent: otherwise the live
    // surface and the core's unmapped snapshot node briefly coexist and the child
    // count changing (2 -> 1) at unmap flips the buffer's Y between frames.
    wf::auxilliary_buffer_t win_snapshot;
    wf::geometry_t snap_box{0, 0, 0, 0};

    OpenGL::program_t program;       // textured piece program
    OpenGL::program_t blade_program; // solid additive blade program

    // cut geometry, chosen once per close
    float nx = 0.0f, ny = 1.0f;   // primary unit cut normal (screen space, y down)
    float nbx = 0.0f, nby = 0.0f; // secondary cut normal (cross/x mode)
    bool cross_mode = false;
    int cuts = 1; // sword strokes; parallel leaves cuts + 1 pieces

    // one swish per stroke, fired as the animation passes each stroke's start
    std::vector<float> sound_times;
    size_t next_sound = 0;
    bool started = false;

    wf::option_wrapper_t<std::string> opt_pattern{"ninjaslash/pattern"};
    wf::option_wrapper_t<int> opt_cuts{"ninjaslash/cuts"};
    wf::option_wrapper_t<bool> opt_random_angle{"ninjaslash/random_angle"};
    wf::option_wrapper_t<double> opt_angle{"ninjaslash/angle"};
    wf::option_wrapper_t<double> opt_spread{"ninjaslash/spread"};
    wf::option_wrapper_t<double> opt_gravity{"ninjaslash/gravity"};
    wf::option_wrapper_t<bool> opt_fade{"ninjaslash/fade"};
    wf::option_wrapper_t<double> opt_curve{"ninjaslash/curve"};
    wf::option_wrapper_t<bool> opt_blade_enabled{"ninjaslash/blade_enabled"};
    wf::option_wrapper_t<wf::color_t> opt_blade_color{"ninjaslash/blade_color"};
    wf::option_wrapper_t<double> opt_blade_width{"ninjaslash/blade_width"};
    wf::option_wrapper_t<bool> opt_sound_enabled{"ninjaslash/sound_enabled"};
    wf::option_wrapper_t<std::string> opt_sound_file{"ninjaslash/sound_file"};
    wf::option_wrapper_t<int> opt_sound_volume{"ninjaslash/sound_volume"};

    void play_sound()
    {
        if (!opt_sound_enabled)
        {
            return;
        }

        std::string file = (std::string)opt_sound_file;
        if (file.empty())
        {
            return;
        }

        // Build the volume literal by hand: pw-play parses it with strtod, which
        // is locale-aware, so a "0.9" would be read as 0 under e.g. es_ES. Force
        // the C locale for the child and keep the string locale-free either way.
        int pct = std::clamp((int)opt_sound_volume, 0, 100);
        std::string vol = (pct >= 100) ? "1.0" :
            ("0." + std::string(pct < 10 ? "0" : "") + std::to_string(pct));

        wf::get_core().run("LC_NUMERIC=C pw-play --volume=" + vol + " '" + file + "'");
    }

    class simple_node_render_instance_t : public wf::scene::transformer_render_instance_t<transformer_base_node_t>
    {
        wf::signal::connection_t<node_damage_signal> on_node_damaged =
            [=] (node_damage_signal *ev)
        {
            push_to_parent(ev->region);
        };

        ninjaslash_transformer *self;
        wayfire_view view;
        damage_callback push_to_parent;

      public:
        simple_node_render_instance_t(ninjaslash_transformer *self, damage_callback push_damage,
            wayfire_view view) : wf::scene::transformer_render_instance_t<transformer_base_node_t>(self,
                push_damage,
                view->get_output())
        {
            this->self = self;
            this->view = view;
            this->push_to_parent = push_damage;
            self->connect(&on_node_damaged);
        }

        void schedule_instructions(
            std::vector<render_instruction_t>& instructions,
            const wf::render_target_t& target, wf::region_t& damage) override
        {
            instructions.push_back(render_instruction_t{
                        .instance = this,
                        .target   = target,
                        .damage   = damage & self->animation_geometry,
                    });
        }

        void transform_damage_region(wf::region_t& damage) override
        {
            damage |= wf::region_t{self->animation_geometry};
        }

        void render(const wf::scene::render_instruction_t& data) override
        {
            auto src_box = self->snap_box;
            auto gl_tex  = wf::gles_texture_t{self->win_snapshot.get_texture()};
            float p = self->progression.progress();

            const float W = std::max(1, src_box.width);
            const float H = std::max(1, src_box.height);
            const float X = src_box.x;
            const float Y = src_box.y;
            const glm::vec2 wc(X + W / 2.0f, Y + H / 2.0f); // window centre, logical

            const glm::vec2 nA(self->nx, self->ny);         // primary cut normal
            const glm::vec2 nB(self->nbx, self->nby);        // secondary (cross/x)
            const bool cross = self->cross_mode;
            const int N = cross ? 4 : (std::max(1, self->cuts) + 1); // pieces

            auto og = self->output->get_relative_geometry();
            float spread  = (float)self->opt_spread;
            float gravity = (float)self->opt_gravity;
            float grav_full = gravity * 0.9f * og.height;
            const float spin_max = 0.5f;
            const float stroke_dur = 0.18f;                  // local blade sweep length
            const float BIG = 1.0e6f;

            // half-extent of the window projected onto the primary cut normal, px
            float R_A = 0.5f * (std::fabs(nA.x) * W + std::fabs(nA.y) * H);

            // Curved cuts: a sword stroke arcs. Model each cut as a circle whose
            // boundary is tangent to the straight cut at its base point, so the
            // parallel cuts become concentric arcs. The radius is kept well above
            // the window diagonal so the window never wraps around the centre.
            float curve = std::clamp((float)self->opt_curve, 0.0f, 1.0f);
            bool curved = curve > 0.01f;
            float win_diag = std::sqrt(W * W + H * H);
            float Rc = curved ? (win_diag * 1.2f / curve) : 0.0f;
            glm::vec2 Ccentre_A = -nA * Rc; // relative to the window centre
            glm::vec2 Ccentre_B = -nB * Rc;

            // Each cut line is a sword stroke, staggered in time so they land in
            // order. Keep them all within the first half of the animation.
            int n_strokes = cross ? 2 : (N - 1);
            float gap = (n_strokes > 0) ? std::min(0.16f, 0.5f / n_strokes) : 0.0f;

            struct Stroke { glm::vec2 n; float offset; float t0; glm::vec2 c; };
            std::vector<Stroke> strokes;
            if (cross)
            {
                strokes.push_back({nA, 0.0f, 0.0f, Ccentre_A});
                strokes.push_back({nB, 0.0f, gap, Ccentre_B});
            } else
            {
                for (int s = 0; s < N - 1; s++)
                {
                    strokes.push_back({nA, -R_A + 2.0f * R_A * (s + 1) / N, s * gap, Ccentre_A});
                }
            }

            struct Piece {
                glm::vec2 bandA, bandB, emaskA, emaskB;
                bool useB;
                glm::vec2 disp;   // full separation displacement (at local t = 1)
                float spin_sign;
                float release;    // progress at which this piece starts moving
            };
            std::vector<Piece> pieces;
            if (cross)
            {
                float rel = gap + stroke_dur * 0.5f; // both cuts done
                float mag = spread * 1.0f * og.width;
                for (int a = -1; a <= 1; a += 2)
                {
                    for (int b = -1; b <= 1; b += 2)
                    {
                        Piece pc;
                        pc.bandA  = (a > 0) ? glm::vec2(0.0f, BIG) : glm::vec2(-BIG, 0.0f);
                        pc.bandB  = (b > 0) ? glm::vec2(0.0f, BIG) : glm::vec2(-BIG, 0.0f);
                        pc.emaskA = (a > 0) ? glm::vec2(1.0f, 0.0f) : glm::vec2(0.0f, 1.0f);
                        pc.emaskB = (b > 0) ? glm::vec2(1.0f, 0.0f) : glm::vec2(0.0f, 1.0f);
                        pc.useB   = true;
                        pc.disp   = (nA * (float)a + nB * (float)b) * mag;
                        pc.spin_sign = 0.5f * (float)a;
                        pc.release   = rel;
                        pieces.push_back(pc);
                    }
                }
            } else
            {
                float mag = spread * 1.4f * og.width;
                for (int k = 0; k < N; k++)
                {
                    float lo = -R_A + 2.0f * R_A * k / N;
                    float hi = -R_A + 2.0f * R_A * (k + 1) / N;
                    float frac = (R_A > 0.0f) ? ((lo + hi) * 0.5f / R_A) : 0.0f;
                    Piece pc;
                    pc.bandA  = glm::vec2(lo, hi);
                    pc.bandB  = glm::vec2(-BIG, BIG);
                    pc.emaskA = glm::vec2(k > 0 ? 1.0f : 0.0f, k < N - 1 ? 1.0f : 0.0f);
                    pc.emaskB = glm::vec2(0.0f, 0.0f);
                    pc.useB   = false;
                    pc.disp   = nA * frac * mag;
                    pc.spin_sign = frac;
                    // freed by its later-indexed bounding stroke
                    pc.release = std::min(k, N - 2) * gap + stroke_dur * 0.5f;
                    pieces.push_back(pc);
                }
            }

            glm::mat4 ortho = wf::gles::render_target_orthographic_projection(data.target);

            data.pass->custom_gles_subpass([&]
            {
                wf::gles::bind_render_buffer(data.target);
                GL_CALL(glDisable(GL_CULL_FACE));
                GL_CALL(glEnable(GL_BLEND));
                GL_CALL(glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA));

                self->program.use(wf::TEXTURE_TYPE_RGBA);
                self->program.set_active_texture(gl_tex);

                std::vector<float> verts = {X, Y, X + W, Y, X + W, Y + H, X, Y + H};
                std::vector<float> uvs   = {0, 0, 1, 0, 1, 1, 0, 1};

                for (auto& pc : pieces)
                {
                    float tp  = (pc.release < 1.0f) ?
                        std::clamp((p - pc.release) / (1.0f - pc.release), 0.0f, 1.0f) : 0.0f;
                    float tpe = tp * tp;                     // accelerate outwards

                    // total end displacement (separation + gravity)
                    glm::vec2 Dend = pc.disp + glm::vec2(0.0f, grav_full);
                    if (!self->opt_fade)
                    {
                        // no fade: make sure every piece clears the screen fully
                        // before the end, so it vanishes off-border, not on-screen.
                        float need = std::sqrt((float)og.width * og.width +
                                (float)og.height * og.height) + std::sqrt(W * W + H * H);
                        float dlen = std::sqrt(Dend.x * Dend.x + Dend.y * Dend.y);
                        if (dlen <= 1.0e-3f)
                        {
                            Dend = glm::vec2(0.0f, need); // stationary piece: drop it out
                        } else if (dlen < need)
                        {
                            Dend *= (need / dlen);
                        }
                    }

                    glm::vec2 fly = Dend * tpe;
                    float spin  = pc.spin_sign * spin_max * tpe;
                    float alpha = self->opt_fade ? (1.0f - smoothstep01(0.65f, 1.0f, tp)) : 1.0f;
                    float edge  = smoothstep01(0.0f, 0.12f, tp) * (1.0f - smoothstep01(0.6f, 1.0f, tp));

                    // model: rotate around window centre, then fly (all in logical px)
                    glm::mat4 m(1.0);
                    m = glm::translate(m, glm::vec3(wc.x + fly.x, wc.y + fly.y, 0.0f));
                    m = glm::rotate(m, spin, glm::vec3(0.0f, 0.0f, 1.0f));
                    m = glm::translate(m, glm::vec3(-wc.x, -wc.y, 0.0f));
                    glm::mat4 matrix = ortho * m;

                    self->program.uniformMatrix4f("matrix", matrix);
                    self->program.uniform2f("winsize", W, H);
                    self->program.uniform2f("cutnA", nA.x * W, nA.y * H);
                    self->program.uniform2f("bandA", pc.bandA.x, pc.bandA.y);
                    self->program.uniform2f("cutnB", nB.x * W, nB.y * H);
                    self->program.uniform2f("bandB", pc.bandB.x, pc.bandB.y);
                    self->program.uniform1f("useB", pc.useB ? 1.0f : 0.0f);
                    self->program.uniform1f("curvedA", curved ? 1.0f : 0.0f);
                    self->program.uniform2f("centerA", Ccentre_A.x, Ccentre_A.y);
                    self->program.uniform1f("radiusA", Rc);
                    self->program.uniform1f("curvedB", curved ? 1.0f : 0.0f);
                    self->program.uniform2f("centerB", Ccentre_B.x, Ccentre_B.y);
                    self->program.uniform1f("radiusB", Rc);
                    self->program.uniform2f("edgemaskA", pc.emaskA.x, pc.emaskA.y);
                    self->program.uniform2f("edgemaskB", pc.emaskB.x, pc.emaskB.y);
                    self->program.uniform1f("alpha", alpha);
                    self->program.uniform1f("edge", edge);
                    self->program.attrib_pointer("position", 2, 0, verts.data());
                    self->program.attrib_pointer("uv_in", 2, 0, uvs.data());
                    GL_CALL(glDrawArrays(GL_TRIANGLE_FAN, 0, 4));
                }

                self->program.deactivate();

                // --- blade streaks: one sweep per stroke, staggered in order ---
                if (self->opt_blade_enabled)
                {
                    wf::color_t bc = self->opt_blade_color;
                    float Whalf = std::max(2.0f, (float)self->opt_blade_width) * 2.4f;
                    bool blade_active = false;

                    for (auto& st : strokes)
                    {
                        float lp = p - st.t0;
                        if (lp <= 0.0f)
                        {
                            continue;
                        }

                        float flash = smoothstep01(0.0f, 0.02f, lp) *
                            (1.0f - smoothstep01(0.28f, 0.42f, lp));
                        if (flash <= 0.001f)
                        {
                            continue;
                        }

                        float glint = std::clamp(lp / stroke_dur, 0.0f, 1.0f);
                        glm::vec2 dir(st.n.y, -st.n.x); // along the cut
                        float L2 = 0.5f * (std::fabs(dir.x) * W + std::fabs(dir.y) * H) + 8.0f;

                        // Trace the cut path and ribbon it. A straight cut needs
                        // only one segment (a quad); an arc is tessellated so the
                        // trail follows exactly the same curve as the cut itself.
                        const int SEG = curved ? 28 : 1;
                        float Rr = Rc + st.offset;
                        float a0 = std::atan2(st.n.y, st.n.x);
                        float dth = (Rr > 1.0f) ? (L2 / Rr) : 0.0f;

                        std::vector<float> bverts, bcoord;
                        bverts.reserve((SEG + 1) * 4);
                        bcoord.reserve((SEG + 1) * 4);

                        for (int i = 0; i <= SEG; i++)
                        {
                            float t = (float)i / SEG;
                            glm::vec2 Prel, radial;
                            if (curved)
                            {
                                float a = a0 + (t * 2.0f - 1.0f) * dth;
                                radial = glm::vec2(std::cos(a), std::sin(a));
                                Prel = st.c + radial * Rr;
                            } else
                            {
                                radial = st.n;
                                Prel = st.n * st.offset + dir * ((t * 2.0f - 1.0f) * L2);
                            }

                            glm::vec2 P  = wc + Prel;
                            glm::vec2 Pa = P - radial * Whalf;
                            glm::vec2 Pb = P + radial * Whalf;
                            bverts.push_back(Pa.x);
                            bverts.push_back(Pa.y);
                            bcoord.push_back(t);
                            bcoord.push_back(-1.0f);
                            bverts.push_back(Pb.x);
                            bverts.push_back(Pb.y);
                            bcoord.push_back(t);
                            bcoord.push_back(1.0f);
                        }

                        if (!blade_active)
                        {
                            self->blade_program.use(wf::TEXTURE_TYPE_RGBA);
                            self->blade_program.uniformMatrix4f("matrix", ortho);
                            self->blade_program.uniform4f("color", glm::vec4(bc.r, bc.g, bc.b, bc.a));
                            blade_active = true;
                        }

                        self->blade_program.uniform1f("glint_pos", glint);
                        self->blade_program.uniform1f("flash", flash);
                        self->blade_program.attrib_pointer("position", 2, 0, bverts.data());
                        self->blade_program.attrib_pointer("coord", 2, 0, bcoord.data());

                        const int bcount = (SEG + 1) * 2;

                        // pass 1: additive glow (reads on dark backgrounds)
                        GL_CALL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
                        self->blade_program.uniform1f("mode", 0.0f);
                        GL_CALL(glDrawArrays(GL_TRIANGLE_STRIP, 0, bcount));

                        // pass 2: opaque core (reads on any background)
                        GL_CALL(glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA));
                        self->blade_program.uniform1f("mode", 1.0f);
                        GL_CALL(glDrawArrays(GL_TRIANGLE_STRIP, 0, bcount));
                    }

                    if (blade_active)
                    {
                        self->blade_program.deactivate();
                    }
                }
            });
        }
    };

    ninjaslash_transformer(wayfire_view view) : wf::scene::view_2d_transformer_t(view)
    {
        this->view = view;

        // capture the window once, now, while it is still mapped
        view->take_snapshot(win_snapshot);
        snap_box = view->get_surface_root_node()->get_bounding_box();

        if (view->get_output())
        {
            output = view->get_output();
            output->render->add_effect(&pre_hook, wf::OUTPUT_EFFECT_PRE);
        }

        animation_geometry = output->get_relative_geometry();
        std::srand((unsigned)std::time(nullptr));

        // choose the pattern (parallel / cross / random)
        std::string pat = (std::string)opt_pattern;
        cuts = std::max(1, (int)opt_cuts);
        if (pat == "cross")
        {
            cross_mode = true;
        } else if (pat == "parallel")
        {
            cross_mode = false;
        } else // "random": fresh pattern every close, ignores the cuts option
        {
            int r = std::rand() % 100;
            if (r < 30)
            {
                cross_mode = true;
            } else
            {
                cross_mode = false;
                cuts = 1 + (std::rand() % 4); // 1..4 cuts -> 2..5 strips
            }
        }

        // choose the slash angle
        double deg;
        if (opt_random_angle)
        {
            deg = 20.0 + (std::rand() / (double)RAND_MAX) * 50.0; // 20..70
            if (std::rand() & 1)
            {
                deg = -deg;
            }
        } else
        {
            deg = (double)opt_angle;
        }

        double th = deg * M_PI / 180.0;
        // cut direction (dir) = (cos, sin); normal = (-sin, cos)
        nx = -(float)std::sin(th);
        ny = (float)std::cos(th);

        // The arc always bows toward +n, so flipping the normal flips which way
        // the stroke curves. Same line either way, just a mirrored sweep.
        if (opt_random_angle && (std::rand() & 1))
        {
            nx = -nx;
            ny = -ny;
        }

        if (cross_mode)
        {
            // second cut perpendicular to the first
            nbx = -ny;
            nby = nx;
        }

        // stroke schedule (must match the one built in render())
        int n_strokes = cross_mode ? 2 : cuts;
        float gap = (n_strokes > 0) ? std::min(0.16f, 0.5f / n_strokes) : 0.0f;
        for (int s = 0; s < n_strokes; s++)
        {
            sound_times.push_back(s * gap);
        }

        wf::gles::run_in_context([&]
        {
            program.compile(piece_vert_source, piece_frag_source);
            GLuint bid = OpenGL::compile_program(blade_vert_source, blade_frag_source);
            blade_program.set_simple(bid, wf::TEXTURE_TYPE_RGBA);
        });
    }

    wf::geometry_t get_bounding_box() override
    {
        return this->animation_geometry;
    }

    wf::effect_hook_t pre_hook = [=] ()
    {
        output->render->damage(animation_geometry);

        // fire one swish per stroke as the animation reaches it. Guarded by
        // `started` because progress() reads 1.0 before the first start().
        if (!started)
        {
            return;
        }

        float p = progression.progress();
        while (next_sound < sound_times.size() && p >= sound_times[next_sound])
        {
            play_sound();
            next_sound++;
        }
    };

    void gen_render_instances(std::vector<render_instance_uptr>& instances,
        damage_callback push_damage, wf::output_t * /*shown_on*/) override
    {
        instances.push_back(std::make_unique<simple_node_render_instance_t>(
            this, push_damage, view));
    }

    void init_animation(bool hiding)
    {
        if (!hiding)
        {
            this->progression.reverse();
        }

        this->progression.start();
        this->started = true;
    }

    virtual ~ninjaslash_transformer()
    {
        if (output)
        {
            output->render->rem_effect(&pre_hook);
        }

        wf::gles::run_in_context_if_gles([&]
        {
            program.free_resources();
            blade_program.free_resources();
        });
    }
};

class ninjaslash_animation : public animation_base_t
{
    wayfire_view view;

  public:
    void init(wayfire_view view, wf::animation_description_t /*dur*/, animation_type type) override
    {
        this->view = view;
        pop_transformer(view);
        auto node = std::make_shared<ninjaslash_transformer>(view);
        view->get_transformed_node()->add_transformer(node, wf::TRANSFORMER_HIGHLEVEL + 1,
            ninjaslash_transformer_name);
        node->init_animation(type & WF_ANIMATE_HIDING_ANIMATION);
    }

    void pop_transformer(wayfire_view view)
    {
        if (view->get_transformed_node()->get_transformer(ninjaslash_transformer_name))
        {
            view->get_transformed_node()->rem_transformer(ninjaslash_transformer_name);
        }
    }

    bool step() override
    {
        if (!view)
        {
            return false;
        }

        auto tmgr = view->get_transformed_node();
        if (!tmgr)
        {
            return false;
        }

        if (auto tr = tmgr->get_transformer<ninjaslash_transformer>(ninjaslash_transformer_name))
        {
            auto running = tr->progression.running();
            if (!running)
            {
                pop_transformer(view);
                return false;
            }

            return running;
        }

        return false;
    }

    void reverse() override
    {
        if (auto tr = view->get_transformed_node()->get_transformer<ninjaslash_transformer>(
            ninjaslash_transformer_name))
        {
            tr->progression.reverse();
        }
    }
};
}
}

class wayfire_ninjaslash : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::animate::animate_effects_registry_t> effects_registry;

  public:
    void init() override
    {
        if (!wf::get_core().is_gles2())
        {
            LOGE("wayfire-ninjaslash: not supported on non-gles2 wayfire");
            return;
        }

        effects_registry->register_effect("ninjaslash", wf::animate::effect_description_t{
            .generator = [] { return std::make_unique<wf::ninjaslash::ninjaslash_animation>(); },
            .default_duration = [] { return wf::ninjaslash::ninjaslash_duration.value(); },
        });
    }

    void fini() override
    {
        effects_registry->unregister_effect("ninjaslash");
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_ninjaslash);
