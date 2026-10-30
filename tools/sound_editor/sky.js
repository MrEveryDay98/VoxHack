// Sky builder (the Sky tab): Quake-style clouds - two scrolling layers,
// generated (layered noise) or pictures, on one flat plane overhead - over
// a plain colour or the day and night sky; and which level gets which sky.
// Saved to mods/nhv_sky/skies.json; the game picks changes up while it
// runs. The preview draws the clouds as the game's shader does
// (client/shaders/nhv_sky_shader); drag it to look around.
"use strict";

const Sky = (() => {
  const LAYER_DEFAULT = {
    kind: "generated", texture: "", speed: [0.01, 0.005], scale: 1, opacity: 1, tint: "#FFFFFF",
    see_through_black: false, coverage: 0.5, softness: 0.15, detail: 4, shade: "#666673",
  };
  const SKY_DEFAULT = {
    id: "sky", name: "New sky",
    layers: [Object.assign({}, LAYER_DEFAULT),
      Object.assign({}, LAYER_DEFAULT, { speed: [0.02, 0.01], scale: 2, opacity: 0.8, coverage: 0.3, softness: 0.1 })],
    horizon: { color: "#000000", fade: 0.6 }, pixels: 64, fog_color: "#000000",
    daynight: false, sun: true, moon: true, stars: true, stars_always: false, cloud_brightness: 1,
    lightning: { on: false, rate: 4, sound: true },
  };
  const LAYER_NAMES = ["Back layer", "Front layer"];

  let data = { version: 1, skies: [], levels: {} };
  let textures = [];
  let levelNames = [];
  let sel = 0;
  let dirty = false;

  const clone = (o) => JSON.parse(JSON.stringify(o));
  const touch = () => { dirty = true; $("#skySave").disabled = false; $("#skyDirty").hidden = false; };

  // (older skies.json entries: fill in what's missing)
  function fill(s) {
    for (const [k, v] of Object.entries(SKY_DEFAULT)) if (s[k] === undefined) s[k] = clone(v);
    s.layers = (s.layers || []).slice(0, 2);
    while (s.layers.length < 2) s.layers.push(clone(LAYER_DEFAULT));
    s.layers.forEach((l) => { for (const [k, v] of Object.entries(LAYER_DEFAULT)) if (l[k] === undefined) l[k] = clone(v); });
    return s;
  }

  async function load() {
    const res = await api("/api/sky");
    data = res.data;
    data.skies.forEach(fill);
    textures = res.textures || [];
    levelNames = res.levels || [];
    render();
  }

  async function save() {
    try {
      const res = await api("/api/sky", { method: "PUT", json: data });
      data.skies = res.skies;
      data.levels = res.levels;
      dirty = false;
      $("#skySave").disabled = true;
      $("#skyDirty").hidden = true;
      toast("Saved. The game picks it up within a second.");
      render();
    } catch (e) { toast("Not saved: " + e.message); }
  }

  // ------------------------------------------------------------ preview (WebGL)
  const VERT = `attribute vec2 pos; void main() { gl_Position = vec4(pos, 0.0, 1.0); }`;
  // (the clouds as client/shaders/nhv_sky_shader draws them; behind them a
  // plain colour, or a rough day/night sky for the preview)
  const FRAG = `precision highp float;
uniform sampler2D t0; uniform sampler2D t1;
uniform vec4 l0; uniform vec4 l1; uniform vec4 tint0; uniform vec4 tint1;
uniform vec4 gen0; uniform vec4 gen1; uniform vec4 shade0; uniform vec4 shade1;
uniform vec4 hz; uniform vec4 misc; uniform vec3 bg; uniform vec3 bgTop; uniform vec4 glow;
uniform vec2 res; uniform float yaw; uniform float pitch; uniform float stars;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p, float oct) {
  float v = 0.0, amp = 0.5, total = 0.0;
  for (int k = 0; k < 6; k++) {
    if (float(k) >= oct) break;
    v += noise(p) * amp; total += amp; p = p * 2.03 + vec2(17.1, 9.7); amp *= 0.5;
  }
  return v / max(total, 0.001);
}
vec4 layer(sampler2D tex, vec2 p, vec4 L, vec4 tint, vec4 gen, vec4 shade) {
  vec2 uv = p * L.z + L.xy;
  if (misc.x > 0.0) uv = (floor(uv * misc.x) + 0.5) / misc.x;
  if (gen.x > 0.5) {
    float n = fbm(uv * 4.0, gen.w), edge = 1.0 - gen.y;
    float a = smoothstep(edge, edge + max(gen.z, 0.01), n);
    vec3 col = mix(shade.rgb, tint.rgb, smoothstep(edge, edge + max(gen.z, 0.01) * 2.0 + 0.15, n));
    return vec4(col, a * L.w);
  }
  vec4 c = texture2D(tex, uv);
  float a = c.a * L.w;
  if (tint.a > 0.5) a *= step(0.02, max(c.r, max(c.g, c.b)));
  return vec4(c.rgb * tint.rgb, a);
}
void main() {
  vec2 uv = (gl_FragCoord.xy / res) * 2.0 - 1.0;
  uv.x *= res.x / res.y;
  vec3 d = normalize(vec3(uv * 0.75, 1.0));
  float cp = cos(pitch), sp = sin(pitch);
  d = vec3(d.x, d.y * cp + d.z * sp, -d.y * sp + d.z * cp);
  float cy = cos(yaw), sy = sin(yaw);
  d = vec3(d.x * cy + d.z * sy, d.y, -d.x * sy + d.z * cy);
  vec3 sky = mix(bg, bgTop, smoothstep(0.0, 0.6, d.y));
  if (stars > 0.0 && d.y > 0.0) {
    vec2 sp2 = floor(d.xz / (d.y + 0.3) * 180.0);
    if (hash(sp2) > 0.997) sky += vec3(stars);
  }
  if (d.y < -0.02) { gl_FragColor = vec4(mix(bg, vec3(0.06), 0.85), 1.0); return; } // (the ground)
  if (d.y <= 0.0) { gl_FragColor = vec4(sky, 1.0); return; }
  vec2 p = d.xz / d.y * 0.25;
  vec4 back = layer(t0, p, l0, tint0, gen0, shade0);
  vec4 front = layer(t1, p, l1, tint1, gen1, shade1);
  float a = back.a + front.a * (1.0 - back.a);
  vec3 col = (back.rgb * back.a * (1.0 - front.a) + front.rgb * front.a) / max(a, 0.001);
  float low = 1.0 - smoothstep(0.05, 0.45, d.y);
  col = mix(col, hz.rgb, low * hz.a);
  a *= smoothstep(0.04, 0.28, d.y);
  col *= mix(vec3(1.0), glow.rgb * 1.5, glow.a);
  gl_FragColor = vec4(mix(sky, col * misc.y, a), 1.0);
}`;

  const view = { yaw: 0, pitch: 0.45, drag: null, canvas: null, gl: null, prog: null, tex: {}, raf: 0, tod: 0.5 };

  function rgb(hex) {
    const m = /^#([0-9a-f]{6})$/i.exec(hex || "");
    const v = m ? parseInt(m[1], 16) : 0xffffff;
    return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
  }
  const mix3 = (a, b, k) => a.map((x, i) => x + (b[i] - x) * k);

  function glTexture(name, smooth) {
    const gl = view.gl;
    const key = name + (smooth ? "|s" : "|n");
    if (view.tex[key]) return view.tex[key];
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
    view.tex[key] = t;
    if (name) {
      const im = new Image();
      im.onload = () => {
        gl.bindTexture(gl.TEXTURE_2D, t);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, im);
        const f = smooth ? gl.LINEAR : gl.NEAREST;
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
      };
      im.src = "/skytex/" + encodeURIComponent(name) + "?v=" + Date.now();
    }
    return t;
  }

  function setupGL(canvas) {
    const gl = canvas.getContext("webgl2") || canvas.getContext("webgl");
    if (!gl) return false;
    const sh = (type, src) => {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER, VERT));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(prog);
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, "pos");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    Object.assign(view, { gl, prog, canvas, tex: {} });
    return true;
  }

  // (roughly Luanti's day and night sky, for the preview: 0 midnight .. 0.5 noon)
  function dayNight(tod) {
    const day = Math.max(0, Math.min(1, (Math.cos((tod - 0.5) * 2 * Math.PI) + 0.25) / 1.25));
    return {
      bg: mix3([0.02, 0.02, 0.06], [0.75, 0.86, 1.0], day),
      top: mix3([0.0, 0.0, 0.03], [0.38, 0.62, 0.98], day),
      light: Math.max(0.12, day), stars: Math.max(0, 1 - day * 2),
    };
  }

  function frame() {
    view.raf = 0;
    const s = data.skies[sel];
    const gl = view.gl;
    if (!s || !gl || !view.canvas.isConnected) return;
    const u = (n) => gl.getUniformLocation(view.prog, n);
    const t = performance.now() / 1000;
    s.layers.forEach((l, i) => {
      const gen = l.kind === "generated";
      gl.activeTexture(gl.TEXTURE0 + i);
      gl.bindTexture(gl.TEXTURE_2D, glTexture(gen ? "" : l.texture, !s.pixels));
      gl.uniform1i(u("t" + i), i);
      const wrap = (v) => (gen ? v % 1000 : v - Math.floor(v));
      gl.uniform4f(u("l" + i), wrap(t * l.speed[0]), wrap(t * l.speed[1]), l.scale, gen || l.texture ? l.opacity : 0);
      const c = rgb(l.tint), sh = rgb(l.shade);
      gl.uniform4f(u("tint" + i), c[0], c[1], c[2], l.see_through_black ? 1 : 0);
      gl.uniform4f(u("gen" + i), gen ? 1 : 0, l.coverage, l.softness, l.detail);
      gl.uniform4f(u("shade" + i), sh[0], sh[1], sh[2], 1);
    });
    const hc = rgb(s.horizon.color);
    gl.uniform4f(u("hz"), hc[0], hc[1], hc[2], s.horizon.fade);
    let bg = rgb(s.fog_color), top = bg, light = 1, stars = 0, glow = [1, 1, 1, 0];
    if (s.daynight) {
      const dn = dayNight(view.tod);
      bg = dn.bg; top = dn.top; light = dn.light; stars = s.stars ? dn.stars : 0;
      // (dawn and dusk: most as the sun's on the horizon - as the game)
      const dw = s.dawn;
      if (dw && dw.on) {
        const off = Math.min(Math.abs(view.tod - 0.2), Math.abs(view.tod - 0.8));
        let k = Math.max(0, Math.min(1, 1 - off / 0.05));
        k = k * k * (3 - 2 * k) * dw.strength;
        bg = mix3(bg, rgb(dw.horizon), k);
        top = mix3(top, rgb(dw.sky), k);
        const c = rgb(dw.clouds);
        glow = [c[0], c[1], c[2], k];
        light = Math.max(light, 0.9 * k); // (lit up by the low sun)
      }
    }
    if (s.stars_always) stars = 1;
    light *= s.cloud_brightness || 1;
    gl.uniform3f(u("bg"), bg[0], bg[1], bg[2]);
    gl.uniform3f(u("bgTop"), top[0], top[1], top[2]);
    gl.uniform4f(u("glow"), glow[0], glow[1], glow[2], glow[3]);
    gl.uniform1f(u("stars"), stars);
    gl.uniform4f(u("misc"), s.pixels || 0, light, 0, 0);
    gl.uniform2f(u("res"), view.canvas.width, view.canvas.height);
    if (!view.drag) view.yaw += 0.0015; // (turns slowly by itself)
    gl.uniform1f(u("yaw"), view.yaw);
    gl.uniform1f(u("pitch"), view.pitch);
    gl.viewport(0, 0, view.canvas.width, view.canvas.height);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    drawLightning(s);
    view.raf = requestAnimationFrame(frame);
  }

  // The sky's lightning, over the preview: now and then (its rate) a jagged,
  // forking bolt across it, and the sky lit up for a moment
  const bolts = [];
  let lastBoltT = performance.now();
  function boltPath(x0, y0, x1, y1, rough, depth, out) {
    let pts = [[x0, y0], [x1, y1]];
    let amp = Math.hypot(x1 - x0, y1 - y0) * rough;
    for (let k = 0; k < 6; k++) {
      const next = [pts[0]];
      for (let i = 0; i < pts.length - 1; i++) {
        const [ax, ay] = pts[i], [bx, by] = pts[i + 1];
        next.push([(ax + bx) / 2 + (Math.random() - 0.5) * amp, (ay + by) / 2 + (Math.random() - 0.5) * amp], pts[i + 1]);
      }
      pts = next;
      amp *= 0.55;
    }
    out.push({ pts, w: depth === 2 ? 2.5 : 1.3 });
    if (depth > 0) {
      for (let i = 8; i < pts.length - 8; i += 16) {
        if (Math.random() < 0.45) {
          const [fx, fy] = pts[i];
          boltPath(fx, fy, fx + (x1 - fx) * 0.4 + (Math.random() - 0.5) * 60, fy + 20 + Math.random() * 50, rough * 1.3, depth - 1, out);
        }
      }
    }
  }
  function drawLightning(s) {
    const ov = view.overlay;
    if (!ov) return;
    const g = ov.getContext("2d");
    g.clearRect(0, 0, ov.width, ov.height);
    const l = s.lightning || {};
    const now = performance.now();
    const dt = (now - lastBoltT) / 1000;
    lastBoltT = now;
    if (l.on && Math.random() < dt * (l.rate || 4) / 60) {
      const W = ov.width, H = ov.height;
      const x = W * (0.15 + Math.random() * 0.7), y = H * (0.1 + Math.random() * 0.35), half = W * (0.12 + Math.random() * 0.15);
      const d = Math.random() < 0.5 ? -1 : 1;
      const lines = [];
      boltPath(x - half * d, y - Math.random() * 20, x + half * d, y + 15 + Math.random() * 40, 0.16, 2, lines);
      bolts.push({ t0: now, lines, flickers: 2 + Math.floor(Math.random() * 3) });
    }
    for (let i = bolts.length - 1; i >= 0; i--) {
      const b = bolts[i], age = (now - b.t0) / 1000;
      if (age > b.flickers * 0.13 + 0.25) { bolts.splice(i, 1); continue; }
      // (the sky lit up, fading)
      g.fillStyle = `rgba(221,230,255,${Math.max(0, 0.28 - age * 0.6)})`;
      g.fillRect(0, 0, ov.width, ov.height);
      if (age > b.flickers * 0.13 || Math.floor(age / 0.065) % 2) continue; // (flickering)
      for (const ln of b.lines) {
        g.beginPath();
        ln.pts.forEach(([px, py], k) => (k ? g.lineTo(px, py) : g.moveTo(px, py)));
        g.strokeStyle = "rgba(159,196,255,0.6)"; g.lineWidth = ln.w * 3; g.stroke();
        g.strokeStyle = "#FFFFFF"; g.lineWidth = ln.w; g.stroke();
      }
    }
  }

  function preview(s) {
    const canvas = el("canvas", { width: 640, height: 360, class: "sky-canvas",
      title: "Drag to look around", "aria-label": "Sky preview" });
    canvas.addEventListener("pointerdown", (e) => { view.drag = { x: e.clientX, y: e.clientY }; canvas.setPointerCapture(e.pointerId); });
    canvas.addEventListener("pointermove", (e) => {
      if (!view.drag) return;
      view.yaw -= (e.clientX - view.drag.x) * 0.006;
      view.pitch = Math.max(-0.3, Math.min(1.5, view.pitch + (e.clientY - view.drag.y) * 0.006));
      view.drag = { x: e.clientX, y: e.clientY };
    });
    canvas.addEventListener("pointerup", () => { view.drag = null; });
    let ok = false;
    try { ok = setupGL(canvas); } catch (e) { toast("Sky preview: " + e.message); }
    if (!ok) return el("p", { class: "muted" }, "(No preview: this browser has no WebGL.)");
    if (!view.raf) view.raf = requestAnimationFrame(frame);
    // (the lightning is drawn over it: drawLightning)
    view.overlay = el("canvas", { width: 640, height: 360, class: "sky-canvas sky-overlay", "aria-hidden": "true" });
    const hours = (v) => { const m = Math.round(v * 1440); return String(Math.floor(m / 60) % 24).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); };
    const out = el("span", { class: "muted" }, hours(view.tod));
    const tod = s.daynight ? el("label", { class: "inline" }, "Preview at",
      el("input", { type: "range", min: 0, max: 1, step: 0.005, value: view.tod, "aria-label": "Preview time of day",
        oninput: (e) => { view.tod = +e.target.value; out.textContent = hours(view.tod); } }), out) : null;
    return el("div", {}, el("div", { class: "sky-stack" }, canvas, view.overlay), tod);
  }

  // ------------------------------------------------------------ editing
  // dawn and dusk (a day and night sky): the sky's colours then, the glow
  // toward the sun, the clouds' colour and how strongly they take it
  function dawnEditor(s) {
    if (!s.dawn) s.dawn = { on: false, sky: "#E8907A", horizon: "#FFB070", sun: "#FF6A2A", clouds: "#FF9A60", strength: 0.6 };
    const dw = s.dawn;
    return el("fieldset", { class: "sky-dawn" }, el("legend", {}, "Dawn and dusk"),
      check(dw, "on", "Colour them (otherwise Luanti's own)", render),
      dw.on ? el("div", {},
        field("Sky", color(dw, "sky"), "Overhead, as the sun rises and sets."),
        field("Horizon", color(dw, "horizon")),
        field("Glow toward the sun", color(dw, "sun"), "The horizon on the sun's side."),
        field("Clouds", color(dw, "clouds"), "Lit by the low sun."),
        field("How strongly the clouds take it", slider(dw, "strength", 0, 1, 0.05, (v) => Math.round(v * 100) + "%"))) : null,
      el("small", { class: "muted" }, "Set \"Preview at\" to about 04:50 or 19:10 to see it."));
  }

  function field(label, input, hint) {
    return el("label", { class: "blk-field" }, label, input, hint ? el("small", { class: "muted" }, hint) : null);
  }

  function slider(obj, key, min, max, step, fmt, idx) {
    const get = () => (idx === undefined ? obj[key] : obj[key][idx]);
    const out = el("span", { class: "muted" }, fmt(get()));
    const input = el("input", { type: "range", min, max, step, value: get(), oninput: (e) => {
      const v = +e.target.value;
      if (idx === undefined) obj[key] = v; else obj[key][idx] = v;
      out.textContent = fmt(v); touch();
    } });
    return el("span", { class: "inline" }, input, out);
  }

  function color(obj, key) {
    return el("input", { type: "color", value: obj[key], oninput: (e) => { obj[key] = e.target.value.toUpperCase(); touch(); } });
  }

  function check(obj, key, label, after) {
    return el("label", { class: "check" }, el("input", { type: "checkbox", checked: obj[key] || null,
      onchange: (e) => { obj[key] = e.target.checked; touch(); if (after) after(); } }), " " + label);
  }

  function texturePicker(l) {
    const select = el("select", { onchange: (e) => { l.texture = e.target.value; touch(); } },
      el("option", { value: "" }, "(none)"),
      ...textures.map((f) => el("option", { value: f, selected: f === l.texture || null }, f)));
    const upload = el("input", { type: "file", accept: "image/png", onchange: async (ev) => {
      const file = ev.target.files[0];
      if (!file) return;
      try {
        const res = await api("/api/sky/texture?name=" + encodeURIComponent(file.name), { method: "POST", body: file });
        if (!textures.includes(res.file)) textures.push(res.file);
        textures.sort();
        // (a re-uploaded picture: drop the preview's old copy)
        Object.keys(view.tex).filter((k) => k.startsWith(res.file + "|")).forEach((k) => delete view.tex[k]);
        l.texture = res.file; touch(); render();
      } catch (e) { toast("Upload failed: " + e.message); }
    } });
    return el("div", { class: "inline" }, select, el("span", { class: "muted" }, "or upload a PNG:"), upload);
  }

  function layerEditor(l, i) {
    const pct = (v) => Math.round(v * 100) + "%";
    const spd = (v) => (+v).toFixed(3) + "/s";
    const gen = l.kind === "generated";
    const kind = el("select", { onchange: (e) => { l.kind = e.target.value; touch(); render(); } },
      el("option", { value: "generated", selected: gen || null }, "Generated clouds"),
      el("option", { value: "texture", selected: !gen || null }, "A picture"));
    const own = gen ? [
      field("Coverage", slider(l, "coverage", 0, 1, 0.01, pct), "How much of the sky the clouds cover."),
      field("Softness", slider(l, "softness", 0, 1, 0.01, pct), "Hard-edged puffs, or soft wisps."),
      field("Detail", slider(l, "detail", 1, 6, 1, (v) => v + (v == 1 ? " level" : " levels")), "Layers of noise: more is finer (and costs a little more)."),
      field("Colour", color(l, "tint")),
      field("Shadow colour", color(l, "shade"), "The thin edges and undersides."),
    ] : [
      field("Picture", texturePicker(l), "Tiles seamlessly."),
      field("Tint", color(l, "tint")),
      check(l, "see_through_black", "Black is see-through (Quake's front clouds)"),
    ];
    return el("div", { class: "sky-layer" },
      el("h4", {}, LAYER_NAMES[i]),
      field("Kind", kind),
      ...own,
      field("Drift east–west", slider(l, "speed", -0.2, 0.2, 0.001, spd, 0)),
      field("Drift north–south", slider(l, "speed", -0.2, 0.2, 0.001, spd, 1)),
      field("Size", slider(l, "scale", 0.2, 8, 0.1, (v) => (+v).toFixed(1) + "x"), "Bigger: smaller, more repeated clouds."),
      field("Opacity", slider(l, "opacity", 0, 1, 0.01, pct)));
  }

  // Lightning shooting across the sky now and then
  function lightningEditor(s) {
    s.lightning = Object.assign({ on: false, rate: 4, sound: true }, s.lightning || {});
    const l = s.lightning;
    return el("div", {},
      el("h4", {}, "Lightning"),
      check(l, "on", "Lightning shoots across the sky now and then", render),
      l.on ? field("How often", slider(l, "rate", 0.5, 60, 0.5, (v) => (+v) + " a minute"),
        "On average: the bolts come at random.") : null,
      l.on ? check(l, "sound", "Thunder (the sound hook sky_thunder, a moment after each bolt)") : null);
  }

  function skyEditor(s) {
    const px = (v) => (+v ? v + " px" : "smooth");
    return el("div", { class: "blk-editor" },
      el("div", { class: "sky-top" },
        el("div", { class: "blk-props" },
          field("Name", el("input", { type: "text", value: s.name, oninput: (e) => { s.name = e.target.value; touch(); } })),
          field("Id", el("input", { type: "text", value: s.id, onchange: (e) => {
            const old = s.id;
            s.id = e.target.value.toLowerCase().replace(/[^a-z0-9_]+/g, "_");
            for (const k of Object.keys(data.levels)) if (data.levels[k] === old) data.levels[k] = s.id;
            touch(); render();
          } }), "Levels refer to the sky by this."),
          field("Pixel size", slider(s, "pixels", 0, 256, 8, px), "Sharp pixels across one repeat of the clouds (0: smooth)."),
          field("Horizon colour", color(s.horizon, "color")),
          field("Horizon fade", slider(s.horizon, "fade", 0, 1, 0.01, (v) => Math.round(v * 100) + "%"), "How strongly the clouds fade into that colour low down."),
          check(s, "daynight", "Day and night (follows the real clock)", render),
          s.daynight ? el("div", { class: "inline" }, check(s, "sun", "Sun"), check(s, "moon", "Moon"), check(s, "stars", "Stars")) : null,
          s.daynight ? dawnEditor(s) : null,
          check(s, "stars_always", "Stars all the time (by day too)", render),
          field("Cloud brightness", slider(s, "cloud_brightness", 0.2, 3, 0.05, (v) => Math.round(v * 100) + "%"),
            "100% is as the clouds are drawn; more makes them glow brighter."),
          s.daynight ? null : field("Sky colour", color(s, "fog_color"),
            "Behind the clouds; distant walls also fade into it on levels open to the sky all over."),
          lightningEditor(s)),
        el("div", { class: "blk-preview" }, preview(s), el("small", { class: "muted" }, "Drag to look around."))),
      el("div", { class: "sky-layers" }, ...s.layers.map(layerEditor)));
  }

  // Which sky where: the default (every level without its own), then every
  // special level, grouped by where it is - a family row ("Medusa's Island
  // (any of them)") sets all its variants, a variant row only that one.
  const openGroups = new Set();
  function levelsEditor() {
    const ids = data.skies.map((s) => s.id);
    if (!ids.length) return null;
    if (!ids.includes(data.levels.default)) data.levels.default = ids[0];
    const skyName = (id) => (data.skies.find((s) => s.id === id) || {}).name || id;
    const known = new Set(["default"]);
    const names = {};
    levelNames.forEach((g) => g.levels.forEach((l) => { known.add(l.id); names[l.id] = l.name; }));
    const pick = (k, blank) => el("select", { onchange: (e) => {
      if (e.target.value) data.levels[k] = e.target.value; else delete data.levels[k];
      touch(); render();
    } },
    blank ? el("option", { value: "", selected: !data.levels[k] || null }, blank) : null,
    ...ids.map((id) => el("option", { value: id, selected: data.levels[k] === id || null }, skyName(id))));
    const row = (l) => {
      const blank = l.of && data.levels[l.of] ? `Same as the rest (${skyName(data.levels[l.of])})`
        : `Default (${skyName(data.levels.default)})`;
      return el("div", { class: "inline sky-level" + (l.of ? " sub" : "") + (data.levels[l.id] ? " set" : "") },
        el("span", { class: "sky-level-name" }, l.family ? el("b", {}, l.name) : l.name, " ", el("small", { class: "muted" }, l.id)),
        pick(l.id, blank));
    };
    const groups = levelNames.map((g) => {
      const n = g.levels.filter((l) => data.levels[l.id]).length;
      const d = el("details", { open: openGroups.has(g.group) || null,
        ontoggle: (e) => { if (e.target.open) openGroups.add(g.group); else openGroups.delete(g.group); } },
      el("summary", {}, g.group, n ? el("small", { class: "muted" }, ` - ${n} with their own sky`) : null),
      ...g.levels.map(row));
      return d;
    });
    // (names set before this list existed, that aren't in it)
    const others = Object.keys(data.levels).filter((k) => !known.has(k)).sort().map((k) =>
      el("div", { class: "inline sky-level set" },
        el("span", { class: "sky-level-name" }, k),
        pick(k, null),
        el("button", { class: "small", onclick: () => { delete data.levels[k]; touch(); render(); } }, "Remove")));
    return el("div", { class: "blk-editor sky-levels" },
      el("h4", {}, "Which sky where"),
      el("div", { class: "inline sky-level" },
        el("span", { class: "sky-level-name" }, el("b", {}, "Default sky")),
        pick("default", null),
        el("small", { class: "muted" }, "Every level that isn't given its own below.")),
      el("p", { class: "muted" }, "A sky only shows where the level is open to it: Medusa's island, Juiblex's swamp, the Big Rooms that can have trees, and any cell whose ceiling you've opened. Ordinary dungeon levels (not special ones) use the default."),
      ...groups,
      others.length ? el("div", {}, el("h4", {}, "Other names"), ...others) : null);
  }

  function render() {
    const root = $("#skyBody");
    if (!root) return;
    if (sel >= data.skies.length) sel = Math.max(0, data.skies.length - 1);
    const list = el("div", { class: "blk-list" },
      ...data.skies.map((s, i) => el("button", { class: "folder blk-item", "aria-pressed": String(i === sel),
        onclick: () => { sel = i; render(); } },
      el("span", { style: `display:inline-block;width:12px;height:12px;border-radius:50%;background:${s.horizon.color}` }),
      el("span", {}, s.name || s.id))),
      el("button", { class: "add", onclick: () => {
        let n = 1;
        while (data.skies.some((x) => x.id === "sky" + n)) n++;
        const s = clone(SKY_DEFAULT);
        s.id = "sky" + n;
        data.skies.push(s); sel = data.skies.length - 1; touch(); render();
      } }, "+ New sky"));
    const s = data.skies[sel];
    const actions = s ? el("div", { class: "inline" },
      el("button", { class: "small", onclick: () => {
        const copy = clone(s);
        copy.id = s.id + "_copy"; copy.name = (s.name || s.id) + " copy";
        data.skies.splice(sel + 1, 0, copy); sel++; touch(); render();
      } }, "Duplicate"),
      el("button", { class: "small", onclick: () => {
        if (!confirm(`Delete the sky "${s.name || s.id}"?`)) return;
        for (const k of Object.keys(data.levels)) if (data.levels[k] === s.id) delete data.levels[k];
        data.skies.splice(sel, 1); touch(); render();
      } }, "Delete")) : null;
    if (view.raf) { cancelAnimationFrame(view.raf); view.raf = 0; }
    root.replaceChildren(el("div", { class: "blk-layout" }, list,
      s ? el("div", {}, actions, skyEditor(s))
        : el("p", { class: "muted" }, "No skies yet: make one with “+ New sky”.")),
    levelsEditor());
  }

  return { load, save, render, isDirty: () => dirty };
})();
