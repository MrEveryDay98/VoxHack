// Sky builder (the Sky tab): Quake-style skies - two scrolling texture
// layers on a flattened dome - and which level gets which. Saved to
// mods/nhv_sky/skies.json; the game picks changes up while it runs. The
// preview draws the sky with the same projection as the game's shader
// (client/shaders/nhv_sky_shader); drag it to look around.
"use strict";

const Sky = (() => {
  const LAYER_DEFAULT = { texture: "", speed: [0.01, 0.006], scale: 3, opacity: 1, tint: "#FFFFFF", see_through_black: false };
  const SKY_DEFAULT = {
    id: "sky", name: "New sky",
    layers: [Object.assign({}, LAYER_DEFAULT), Object.assign({}, LAYER_DEFAULT, { speed: [0.025, 0.012], see_through_black: true })],
    horizon: { color: "#000000", fade: 0.6 }, smooth: false, fog_color: "#000000",
  };
  const LAYER_NAMES = ["Back layer", "Front layer"];

  let data = { version: 1, skies: [], levels: {} };
  let textures = [];
  let levelNames = [];
  let sel = 0;
  let dirty = false;

  const clone = (o) => JSON.parse(JSON.stringify(o));
  const touch = () => { dirty = true; $("#skySave").disabled = false; $("#skyDirty").hidden = false; };

  async function load() {
    const res = await api("/api/sky");
    data = res.data;
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
  const FRAG = `precision highp float;
uniform sampler2D t0; uniform sampler2D t1;
uniform vec4 l0; uniform vec4 l1; uniform vec4 tint0; uniform vec4 tint1; uniform vec4 hz;
uniform vec2 res; uniform float yaw; uniform float pitch;
void main() {
  vec2 uv = (gl_FragCoord.xy / res) * 2.0 - 1.0;
  uv.x *= res.x / res.y;
  vec3 d = normalize(vec3(uv * 0.75, 1.0));
  float cp = cos(pitch), sp = sin(pitch);
  d = vec3(d.x, d.y * cp + d.z * sp, -d.y * sp + d.z * cp);
  float cy = cos(yaw), sy = sin(yaw);
  d = vec3(d.x * cy + d.z * sy, d.y, -d.x * sy + d.z * cy);
  vec3 f = vec3(d.x, abs(d.y) * 3.0, d.z);
  vec2 p = d.xz / length(f);
  vec4 back = texture2D(t0, p * l0.z + l0.xy);
  vec4 front = texture2D(t1, p * l1.z + l1.xy);
  vec3 col = back.rgb * tint0.rgb * (back.a * l0.w);
  float a1 = front.a * l1.w;
  if (tint1.a > 0.5) a1 *= step(0.02, max(front.r, max(front.g, front.b)));
  col = mix(col, front.rgb * tint1.rgb, a1);
  float h = 1.0 - smoothstep(0.0, 0.35, abs(d.y));
  col = mix(col, hz.rgb, h * hz.a);
  if (d.y < -0.02) col = mix(col, vec3(0.06), 0.85); // (the ground, for the preview)
  gl_FragColor = vec4(col, 1.0);
}`;

  const view = { yaw: 0, pitch: 0.35, drag: null, canvas: null, gl: null, prog: null, tex: {}, raf: 0 };

  function rgb(hex) {
    const m = /^#([0-9a-f]{6})$/i.exec(hex || "");
    const v = m ? parseInt(m[1], 16) : 0xffffff;
    return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
  }

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

  function frame() {
    view.raf = 0;
    const s = data.skies[sel];
    const gl = view.gl;
    if (!s || !gl || !view.canvas.isConnected) return;
    const u = (n) => gl.getUniformLocation(view.prog, n);
    const t = performance.now() / 1000;
    s.layers.forEach((l, i) => {
      gl.activeTexture(gl.TEXTURE0 + i);
      gl.bindTexture(gl.TEXTURE_2D, glTexture(l.texture, s.smooth));
      gl.uniform1i(u("t" + i), i);
      const fr = (v) => v - Math.floor(v);
      gl.uniform4f(u("l" + i), fr(t * l.speed[0]), fr(t * l.speed[1]), l.scale, l.texture ? l.opacity : 0);
      const c = rgb(l.tint);
      gl.uniform4f(u("tint" + i), c[0], c[1], c[2], l.see_through_black ? 1 : 0);
    });
    const hc = rgb(s.horizon.color);
    gl.uniform4f(u("hz"), hc[0], hc[1], hc[2], s.horizon.fade);
    gl.uniform2f(u("res"), view.canvas.width, view.canvas.height);
    if (!view.drag) view.yaw += 0.0015; // (turns slowly by itself)
    gl.uniform1f(u("yaw"), view.yaw);
    gl.uniform1f(u("pitch"), view.pitch);
    gl.viewport(0, 0, view.canvas.width, view.canvas.height);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    view.raf = requestAnimationFrame(frame);
  }

  function preview() {
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
    return canvas;
  }

  // ------------------------------------------------------------ editing
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
    return el("div", { class: "sky-layer" },
      el("h4", {}, LAYER_NAMES[i]),
      field("Picture", texturePicker(l), "Tiles seamlessly; " + (i === 0 ? "drawn first, over black." : "drawn over the back layer.")),
      field("Scroll east–west", slider(l, "speed", -0.2, 0.2, 0.001, spd, 0)),
      field("Scroll north–south", slider(l, "speed", -0.2, 0.2, 0.001, spd, 1)),
      field("Size", slider(l, "scale", 0.5, 12, 0.1, (v) => (+v).toFixed(1) + "x"), "How many times the picture repeats across the sky (Quake's is about 3)."),
      field("Opacity", slider(l, "opacity", 0, 1, 0.01, pct)),
      field("Tint", el("input", { type: "color", value: l.tint, oninput: (e) => { l.tint = e.target.value.toUpperCase(); touch(); } })),
      el("label", { class: "check" }, el("input", { type: "checkbox", checked: l.see_through_black || null,
        onchange: (e) => { l.see_through_black = e.target.checked; touch(); } }), " Black is see-through (Quake's front clouds)"));
  }

  function skyEditor(s) {
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
          field("Horizon colour", el("input", { type: "color", value: s.horizon.color, oninput: (e) => { s.horizon.color = e.target.value.toUpperCase(); touch(); } })),
          field("Horizon fade", slider(s.horizon, "fade", 0, 1, 0.01, (v) => Math.round(v * 100) + "%"), "How strongly the sky fades into that colour low down."),
          field("Fog colour", el("input", { type: "color", value: s.fog_color, oninput: (e) => { s.fog_color = e.target.value.toUpperCase(); touch(); } }),
            "Distant walls fade into this on levels open to the sky all over (usually the horizon colour)."),
          el("label", { class: "check" }, el("input", { type: "checkbox", checked: s.smooth || null,
            onchange: (e) => { s.smooth = e.target.checked; view.tex = {}; touch(); } }), " Smooth (filtered) pictures instead of sharp pixels")),
        el("div", { class: "blk-preview" }, preview(), el("small", { class: "muted" }, "Drag to look around."))),
      el("div", { class: "sky-layers" }, ...s.layers.map(layerEditor)));
  }

  function levelsEditor() {
    const ids = data.skies.map((s) => s.id);
    if (!data.levels.default && ids.length) data.levels.default = ids[0];
    const list = el("datalist", { id: "skyLevelNames" }, ...levelNames.map((n) => el("option", { value: n })));
    const rows = Object.keys(data.levels).sort((a, b) => (a === "default" ? -1 : b === "default" ? 1 : a.localeCompare(b))).map((k) =>
      el("div", { class: "inline sky-level" },
        el("span", { class: "sky-level-name" }, k === "default" ? "Every other level" : k),
        el("select", { onchange: (e) => { data.levels[k] = e.target.value; touch(); } },
          ...ids.map((id) => el("option", { value: id, selected: data.levels[k] === id || null }, (data.skies.find((s) => s.id === id) || {}).name || id))),
        k === "default" ? null : el("button", { class: "small", onclick: () => { delete data.levels[k]; touch(); render(); } }, "Remove")));
    const name = el("input", { type: "text", list: "skyLevelNames", placeholder: "medusa, bigrm-6, juiblex...", style: "width:16em" });
    const add = el("button", { class: "small", onclick: () => {
      const k = name.value.trim().toLowerCase();
      if (!/^[a-z0-9_-]{1,40}$/.test(k)) return toast("A level name: like medusa or bigrm-6");
      if (!ids.length) return toast("Make a sky first.");
      data.levels[k] = data.levels.default || ids[0]; touch(); render();
    } }, "Add level");
    return el("div", { class: "blk-editor" },
      el("h4", {}, "Which sky where"),
      el("p", { class: "muted" }, "Only levels with the sky over them show one: Medusa's island, Juiblex's swamp, the Big Rooms that can have trees, and any level with a cell whose ceiling is open. A level can be a special level's variant (bigrm-6) or its family (bigrm, medusa)."),
      list, ...rows, el("div", { class: "inline" }, name, add));
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
      s ? el("div", {}, actions, skyEditor(s), levelsEditor())
        : el("p", { class: "muted" }, "No skies yet: make one with “+ New sky”.")));
  }

  return { load, save, render, isDirty: () => dirty };
})();
