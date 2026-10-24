// Particle effect builder (the Effects tab): effects made here play in the
// game when one of their triggers (the same hooks sounds attach to) fires.
// Saved to mods/nhv_effects/effects.json; the game picks changes up while
// it runs. The preview approximates what the game draws.
"use strict";

const Effects = (() => {
  const SHAPES = [
    ["burst", "Burst (outward in all directions)"], ["ring", "Ring (outward along the ground)"],
    ["implode", "Implode (pulled into the middle)"], ["rise", "Rise (float up)"], ["rain", "Rain (fall from above)"],
  ];
  const BUILTIN = ["dot", "spark", "star", "square", "ring"];
  const GROUPS = [["loops", "Loops: play without a break while it lasts"], ["traps", "Traps"], ["events", "Actions & events"], ["game", "Game"], ["nethack", "NetHack sounds"], ["music", "Music"]];
  const LAYER_DEFAULT = {
    shape: "burst", texture: { builtin: "dot" }, color: "#FFFFFF", amount: 30, duration: 0.3, spread: 0.4,
    height: 1, speed: [1, 3], life: [0.5, 1.2], size: [1, 2], gravity: 0, glow: 10, additive: true, fade: true, collide: false,
  };

  let data = { version: 1, effects: [] };
  let textures = [];
  let sheet = { cols: 48, rows: 25, names: {} };
  let hooks = [];
  let sel = 0, layerSel = 0;
  let dirty = false;
  let hookQuery = "";

  const touch = () => { dirty = true; $("#fxSave").disabled = false; $("#fxDirty").hidden = false; replay(); };
  const clone = (o) => JSON.parse(JSON.stringify(o));

  async function load() {
    const res = await api("/api/effects");
    data = res.data;
    textures = res.textures;
    sheet = res.sheet;
    hooks = res.hooks || [];
    render();
  }

  async function save() {
    try {
      const res = await api("/api/effects", { method: "PUT", json: data });
      data.effects = res.effects;
      dirty = false;
      $("#fxSave").disabled = true;
      $("#fxDirty").hidden = true;
      toast("Saved. The game picks it up within a couple of seconds.");
      render();
    } catch (e) { toast("Not saved: " + e.message); }
  }

  // ------------------------------------------------------------ textures
  const images = {};
  function image(src) {
    if (!images[src]) {
      const im = new Image();
      im.src = src;
      images[src] = im;
    }
    return images[src];
  }
  // the particle's picture, tinted, as a canvas (cached)
  const tinted = {};
  function particleImage(l) {
    const t = l.texture || {};
    const key = JSON.stringify(t) + l.color;
    if (tinted[key]) return tinted[key];
    let src, sx = 0, sy = 0, sw = 0, sh = 0;
    if (t.builtin) src = `/fxtex/nhvfx_${t.builtin}.png`;
    else if (t.file) src = `/fxtex/${t.file}`;
    else if (t.sheet !== undefined) src = "/sheet.png";
    else src = "/fxtex/nhvfx_dot.png";
    const im = image(src);
    if (!im.complete || !im.naturalWidth) return null;
    if (t.sheet !== undefined) {
      const size = im.naturalWidth / sheet.cols;
      sx = (t.sheet % sheet.cols) * size; sy = Math.floor(t.sheet / sheet.cols) * size; sw = sh = size;
    } else { sw = im.naturalWidth; sh = im.naturalHeight; }
    const c = document.createElement("canvas");
    c.width = sw; c.height = sh;
    const g = c.getContext("2d");
    g.imageSmoothingEnabled = false;
    g.drawImage(im, sx, sy, sw, sh, 0, 0, sw, sh);
    if ((l.color || "#FFFFFF").toUpperCase() !== "#FFFFFF") {
      g.globalCompositeOperation = "multiply";
      g.fillStyle = l.color;
      g.fillRect(0, 0, sw, sh);
      g.globalCompositeOperation = "destination-in";
      g.drawImage(im, sx, sy, sw, sh, 0, 0, sw, sh);
    }
    tinted[key] = c;
    return c;
  }

  // ------------------------------------------------------------ preview
  // a rough copy of what the game does (effects.lua), seen from the side
  const S = 70; // pixels per block
  let canvas = null, particles = [], t0 = 0, loop = true, raf = null, effectLen = 1;
  const rnd = (a, b) => a + Math.random() * (b - a);
  function randDir() {
    const z = rnd(-1, 1), a = rnd(0, Math.PI * 2), r = Math.sqrt(1 - z * z);
    return [r * Math.cos(a), z, r * Math.sin(a)];
  }

  function spawnAll(e) {
    particles = [];
    effectLen = 0.5;
    for (const l of e.layers || []) {
      const [s1, s2] = l.speed, [e1, e2] = l.life;
      const spread = Math.max(0.05, l.spread);
      effectLen = Math.max(effectLen, l.duration + e2 + 0.4);
      for (let i = 0; i < l.amount; i++) {
        const p = { l, born: rnd(0, l.duration), life: rnd(e1, e2), size: rnd(l.size[0], l.size[1]), acc: -l.gravity };
        const cy = l.height;
        if (l.shape === "burst" || l.shape === "ring") {
          const r = Math.max(0.05, spread * 0.5);
          let d = randDir();
          if (l.shape === "ring") { d = [d[0], 0, d[2]]; const n = Math.hypot(d[0], d[2]) || 1; d = [d[0] / n, 0, d[2] / n]; }
          const sp = rnd(s1, s2);
          p.pos = [d[0] * r, cy + d[1] * r, d[2] * r];
          p.vel = [d[0] * sp, d[1] * sp, d[2] * sp];
        } else if (l.shape === "implode") {
          const d = randDir(), sp = rnd(s1, s2);
          p.pos = [d[0] * spread, cy + d[1] * spread, d[2] * spread];
          p.vel = [-d[0] * sp, -d[1] * sp, -d[2] * sp];
          p.life = Math.min(p.life, spread / sp); // dies at the middle
        } else if (l.shape === "rain") {
          p.pos = [rnd(-spread, spread), cy + rnd(1.5, 2), rnd(-spread, spread)];
          p.vel = [0, -rnd(s1, s2), 0];
        } else {
          p.pos = [rnd(-spread, spread), cy + rnd(0, 0.2), rnd(-spread, spread)];
          p.vel = [rnd(-0.15, 0.15) * s1, rnd(s1, s2), rnd(-0.15, 0.15) * s1];
        }
        particles.push(p);
      }
    }
    t0 = performance.now();
  }

  function frame() {
    raf = null;
    if (!canvas || !canvas.isConnected) return;
    const e = data.effects[sel];
    const g = canvas.getContext("2d");
    const W = canvas.width, H = canvas.height, cx = W / 2, gy = H - 40;
    g.globalCompositeOperation = "source-over";
    g.globalAlpha = 1;
    g.fillStyle = "#08080c";
    g.fillRect(0, 0, W, H);
    // floor and a hero-sized figure for scale
    g.fillStyle = "#1c1c26";
    g.fillRect(0, gy, W, H - gy);
    g.fillStyle = "#2e2e3c";
    g.fillRect(cx - 0.3 * S, gy - 1.75 * S, 0.6 * S, 1.75 * S);
    const t = (performance.now() - t0) / 1000;
    g.imageSmoothingEnabled = false;
    for (const p of particles) {
      const age = t - p.born;
      if (age < 0 || age > p.life) continue;
      const x = p.pos[0] + p.vel[0] * age, z = p.pos[2] + p.vel[2] * age;
      const y = p.pos[1] + p.vel[1] * age + 0.5 * p.acc * age * age;
      if (p.l.collide && y < 0) continue;
      const sx = cx + (x * 0.9 + z * 0.4) * S, sy = gy - (y + z * 0.15) * S;
      const px = Math.max(2, p.size * 0.1 * S);
      const im = particleImage(p.l);
      g.globalCompositeOperation = p.l.additive ? "lighter" : "source-over";
      g.globalAlpha = p.l.fade ? Math.max(0, 1 - age / p.life) : 1;
      if (im) g.drawImage(im, sx - px / 2, sy - px / 2, px, px);
      else { g.fillStyle = p.l.color; g.fillRect(sx - px / 2, sy - px / 2, px, px); }
    }
    if (e && loop && t > effectLen) spawnAll(e);
    raf = requestAnimationFrame(frame);
  }

  function replay() {
    const e = data.effects[sel];
    if (!e) return;
    spawnAll(e);
    if (!raf) raf = requestAnimationFrame(frame);
  }

  // ------------------------------------------------------------ editing
  function field(label, input, hint) {
    return el("label", { class: "blk-field" }, el("span", {}, label), input,
      hint ? el("small", { class: "muted" }, hint) : null);
  }
  const num = (obj, k, min, max, step) => el("input", { type: "number", value: obj[k], min, max, step,
    onchange: (ev) => { obj[k] = +ev.target.value; touch(); } });
  const pair = (obj, k, min, max, step) => el("span", { class: "inline", style: "margin:0" },
    el("input", { type: "number", value: obj[k][0], min, max, step, style: "width:6em",
      onchange: (ev) => { obj[k][0] = +ev.target.value; touch(); } }), "to",
    el("input", { type: "number", value: obj[k][1], min, max, step, style: "width:6em",
      onchange: (ev) => { obj[k][1] = +ev.target.value; touch(); } }));
  const check = (obj, k, label) => el("label", { class: "check" },
    el("input", { type: "checkbox", checked: obj[k] || null, onchange: (ev) => { obj[k] = ev.target.checked; touch(); } }), label);

  function texturePicker(l) {
    const t = l.texture || {};
    const thumb = (tex, title, on) => {
      const c = el("canvas", { width: 32, height: 32, class: "tex" + (on ? " on" : ""), title, style: "image-rendering:pixelated;background:#0b0b10" });
      const draw = () => {
        const im = particleImage({ texture: tex, color: l.color });
        if (!im) return setTimeout(draw, 150);
        const g = c.getContext("2d");
        g.imageSmoothingEnabled = false;
        g.clearRect(0, 0, 32, 32);
        g.drawImage(im, 4, 4, 24, 24);
      };
      draw();
      c.addEventListener("click", () => { l.texture = tex; touch(); render(); });
      return c;
    };
    const builtins = el("div", { class: "blk-grid", style: "max-height:none" },
      ...BUILTIN.map((b) => thumb({ builtin: b }, b, t.builtin === b)),
      ...textures.map((f) => thumb({ file: f }, f, t.file === f)));
    const upload = el("input", { type: "file", accept: "image/png", onchange: async (ev) => {
      const file = ev.target.files[0];
      if (!file) return;
      try {
        const res = await api("/api/effects/texture?name=" + encodeURIComponent(file.name), { method: "POST", body: file });
        if (!textures.includes(res.file)) textures.push(res.file);
        l.texture = { file: res.file }; touch(); render();
      } catch (e) { toast("Upload failed: " + e.message); }
    } });
    const sheetNo = el("input", { type: "number", min: 0, max: sheet.cols * sheet.rows - 1, style: "width:7em",
      value: t.sheet !== undefined ? t.sheet : "", placeholder: "sprite #",
      onchange: (ev) => { if (ev.target.value !== "") { l.texture = { sheet: +ev.target.value }; touch(); render(); } } });
    const sheetName = t.sheet !== undefined ? (sheet.names[String(t.sheet)] || "") : "";
    return el("div", { class: "blk-texpick" }, builtins,
      el("div", { class: "inline" }, el("span", { class: "muted" }, "Or a sprite from the sheet:"), sheetNo,
        t.sheet !== undefined ? el("span", { class: "muted" }, sheetName) : null),
      el("div", { class: "inline" }, el("span", { class: "muted" }, "Or your own PNG (white parts take the colour):"), upload));
  }

  function layerEditor(l) {
    return el("div", { class: "blk-props" },
      field("Shape", el("select", { onchange: (ev) => { l.shape = ev.target.value; touch(); } },
        ...SHAPES.map(([k, lab]) => el("option", { value: k, selected: l.shape === k || null }, lab)))),
      el("div", { class: "inline" },
        field("Colour", el("input", { type: "color", value: l.color, onchange: (ev) => { l.color = ev.target.value.toUpperCase(); touch(); render(); } })),
        field("Particles", num(l, "amount", 1, 400, 1)),
        field("Over (seconds)", num(l, "duration", 0.05, 10, 0.05)),
        field("Glow", num(l, "glow", 0, 14, 1), "0 = lit like the room, 14 = shines")),
      el("div", { class: "inline" },
        field("Spread (blocks)", num(l, "spread", 0, 4, 0.1)),
        field("Height (blocks)", num(l, "height", -1, 4, 0.1), "above the floor"),
        field("Gravity", num(l, "gravity", -20, 20, 0.5), "negative floats up")),
      field("Speed (blocks/s)", pair(l, "speed", 0, 30, 0.1)),
      field("Lifetime (seconds)", pair(l, "life", 0.05, 10, 0.05)),
      field("Size", pair(l, "size", 0.1, 20, 0.1), "10 = one block"),
      el("div", { class: "inline" }, check(l, "additive", "Glowy (adds light)"), check(l, "fade", "Fade out"),
        check(l, "collide", "Stop at walls and floor")),
      el("h4", {}, "Particle"), texturePicker(l));
  }

  function triggerPicker(e) {
    const on = new Set(e.triggers || []);
    const q = hookQuery.trim().toLowerCase();
    const groups = el("div", { class: "fx-hooks" });
    for (const [gk, gl] of GROUPS) {
      const hs = hooks.filter((h) => h.group === gk && (!q || h.id.includes(q) || (h.desc || "").toLowerCase().includes(q)));
      if (!hs.length) continue;
      groups.append(el("div", { class: "blk-group" }, gl));
      for (const h of hs) {
        groups.append(el("label", { class: "check", title: h.desc || h.id },
          el("input", { type: "checkbox", checked: on.has(h.id) || null, onchange: (ev) => {
            if (ev.target.checked) on.add(h.id); else on.delete(h.id);
            e.triggers = [...on].sort(); touch(); render();
          } }), h.id.replace(/_/g, " "), h.desc && h.desc !== h.id.replace(/_/g, " ")
            ? el("small", { class: "muted" }, " — " + h.desc) : null));
      }
    }
    return el("div", {},
      el("div", { class: "chips", style: "margin-bottom:6px" }, ...(e.triggers || []).map((id) =>
        el("button", { class: "chip", "aria-pressed": "true", title: "Remove", onclick: () => {
          e.triggers = e.triggers.filter((x) => x !== id); touch(); render();
        } }, id.replace(/_/g, " ") + " ×"))),
      el("input", { type: "search", placeholder: "Search triggers (trap, read, zap...)", value: hookQuery,
        oninput: (ev) => { hookQuery = ev.target.value; render(); const s = $("#effectsBody input[type=search]"); s.focus(); s.setSelectionRange(s.value.length, s.value.length); } }),
      groups);
  }

  function editor(e) {
    if (layerSel >= e.layers.length) layerSel = e.layers.length - 1;
    const l = e.layers[layerSel];
    canvas = el("canvas", { width: 420, height: 320, style: "width:100%;max-width:420px;border-radius:8px" });
    const layerTabs = el("div", { class: "chips" },
      ...e.layers.map((_, i) => el("button", { class: "chip", "aria-pressed": String(i === layerSel),
        onclick: () => { layerSel = i; render(); } }, "Layer " + (i + 1))),
      e.layers.length < 6 ? el("button", { class: "chip", onclick: () => {
        e.layers.push(clone(LAYER_DEFAULT)); layerSel = e.layers.length - 1; touch(); render();
      } }, "+ Layer") : null,
      e.layers.length > 1 ? el("button", { class: "chip", onclick: () => {
        e.layers.splice(layerSel, 1); touch(); render();
      } }, "Remove this layer") : null);
    const view = el("div", { class: "blk-editor" },
      el("div", { class: "blk-top" },
        el("div", { class: "blk-preview" }, canvas,
          el("div", { class: "inline" },
            el("button", { class: "small", onclick: replay }, "Play again"),
            el("label", { class: "check" }, el("input", { type: "checkbox", checked: loop || null,
              onchange: (ev) => { loop = ev.target.checked; } }), "Loop")),
          el("small", { class: "muted" }, "A rough preview, seen from the side; the grey shape is the hero.")),
        el("div", { class: "blk-props" },
          field("Name", el("input", { type: "text", value: e.name, onchange: (ev) => { e.name = ev.target.value; touch(); render(); } })),
          field("Id", el("input", { type: "text", value: e.id, onchange: (ev) => { e.id = ev.target.value; touch(); render(); } })),
          el("h4", {}, "Plays when"), triggerPicker(e))),
      el("h4", {}, "Layers"), layerTabs, layerEditor(l));
    setTimeout(replay, 0);
    return view;
  }

  function render() {
    const root = $("#effectsBody");
    if (!root) return;
    if (sel >= data.effects.length) sel = Math.max(0, data.effects.length - 1);
    const list = el("div", { class: "blk-list" },
      ...data.effects.map((e, i) => el("button", { class: "folder blk-item", "aria-pressed": String(i === sel),
        onclick: () => { sel = i; layerSel = 0; render(); } },
      el("span", { style: `display:inline-block;width:12px;height:12px;border-radius:50%;background:${(e.layers[0] || {}).color || "#fff"}` }),
      el("span", {}, e.name || e.id), e.triggers && e.triggers.length ? null : el("small", { class: "muted" }, "(no trigger)"))),
      el("button", { class: "add", onclick: () => {
        let n = 1;
        while (data.effects.some((x) => x.id === "effect" + n)) n++;
        data.effects.push({ id: "effect" + n, name: "New effect", layers: [clone(LAYER_DEFAULT)], triggers: [] });
        sel = data.effects.length - 1; layerSel = 0; touch(); render();
      } }, "+ New effect"));
    const e = data.effects[sel];
    const actions = e ? el("div", { class: "inline" },
      el("button", { class: "small", onclick: () => {
        const copy = clone(e);
        copy.id = e.id + "_copy"; copy.name = (e.name || e.id) + " copy"; copy.triggers = [];
        data.effects.splice(sel + 1, 0, copy); sel++; touch(); render();
      } }, "Duplicate"),
      el("button", { class: "small", onclick: () => {
        if (!confirm(`Delete the effect "${e.name || e.id}"?`)) return;
        data.effects.splice(sel, 1); touch(); render();
      } }, "Delete")) : null;
    root.replaceChildren(el("div", { class: "blk-layout" }, list,
      e ? el("div", {}, actions, editor(e)) : el("p", { class: "muted" }, "No effects yet: make one with “+ New effect”.")));
  }

  return { load, save, render, isDirty: () => dirty };
})();
