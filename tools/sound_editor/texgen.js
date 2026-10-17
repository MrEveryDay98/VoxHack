// Texture generator (the Blocks tab's "Generate" picker): small pixel
// textures made from a pattern - rings, waves, a swirl, plasma, noise, a
// glow - coloured by a hue cycle or a gradient, posterized to a few shades
// (dithered if asked). With more than one frame it's an animation: the
// frames stacked top to bottom, the pattern moving through one loop (the
// game plays it back as the block's animated texture). Saved as one of
// "your pictures" (mods/nhv_blocks/textures).
"use strict";

const TexGen = (() => {
  const PATTERNS = [
    ["rings", "Rings"], ["waves", "Waves"], ["swirl", "Swirl"],
    ["plasma", "Plasma"], ["noise", "Noise"], ["glow", "Radial glow"],
  ];
  const opts = {
    pattern: "rings", size: 16, freq: 2, twist: 1, arms: 3, angle: 0,
    colors: "hue", hueStart: 225, hueRange: 110, sat: 60, light: 62,
    c1: "#3a2a8c", c2: "#9a6cff", c3: "#e8f0ff", use3: true,
    levels: 8, dither: false, frames: 1, length: 1, seed: 1, name: "generated",
  };

  // ------------------------------------------------------------ the pattern
  function hash(x, y, s) {
    let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0;
    h = (h ^ (h >>> 13)) * 1274126177;
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }
  // value noise that tiles every `p` cells
  function vnoise(x, y, p, s) {
    const xi = Math.floor(x), yi = Math.floor(y), fx = x - xi, fy = y - yi;
    const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
    const m = (a) => ((a % p) + p) % p;
    const a = hash(m(xi), m(yi), s), b = hash(m(xi + 1), m(yi), s);
    const c = hash(m(xi), m(yi + 1), s), d = hash(m(xi + 1), m(yi + 1), s);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  // the pattern at pixel (x, y) of an n-pixel texture, frame phase t (0..1): 0..1
  function value(o, x, y, n, t) {
    const px = (x + 0.5) / n, py = (y + 0.5) / n; // 0..1 across the texture
    const cx = px - 0.5, cy = py - 0.5;
    const r = Math.hypot(cx, cy), a = Math.atan2(cy, cx);
    const ph = t * 2 * Math.PI;
    const f = o.freq;
    let v;
    switch (o.pattern) {
      case "rings": v = Math.sin(r * f * 2 * Math.PI * 2 - ph); break;
      case "waves": {
        const ang = o.angle * Math.PI / 180;
        // (whole waves across the texture: it tiles)
        v = Math.sin((px * Math.round(f * Math.cos(ang)) + py * Math.round(f * Math.sin(ang))) * 2 * Math.PI - ph);
        if (!Math.round(f * Math.cos(ang)) && !Math.round(f * Math.sin(ang))) v = Math.sin(px * f * 2 * Math.PI - ph);
        break;
      }
      case "swirl": v = Math.sin(a * o.arms + r * o.twist * 2 * Math.PI * 2 - ph); break;
      case "plasma": {
        const k = f * 2 * Math.PI;
        v = (Math.sin(px * k + ph) + Math.sin(py * k - ph) + Math.sin((px + py) * k / 2 + ph)
          + Math.sin(Math.hypot(cx, cy) * k * 1.5 - ph)) / 4;
        break;
      }
      case "noise": {
        // (it scrolls by one period over the loop: seamless)
        const p = Math.max(2, Math.round(f));
        let s = 0, amp = 0.5, tot = 0;
        for (let k = 0, q = p; k < 4; k++, q *= 2) {
          s += vnoise(px * q + t * q, py * q, q, o.seed + k) * amp; tot += amp; amp *= 0.5;
        }
        return s / tot;
      }
      case "glow": v = 1 - Math.min(1, r * 2) * 2 + 0.25 * Math.sin(ph); break;
      default: v = 0;
    }
    return Math.max(0, Math.min(1, v * 0.5 + 0.5));
  }

  const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

  function hexRgb(h) {
    const v = parseInt((h || "#000000").slice(1), 16);
    return [v >> 16 & 255, v >> 8 & 255, v & 255];
  }
  function hslRgb(h, s, l) {
    h = ((h % 360) + 360) % 360; s /= 100; l /= 100;
    const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
    const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
      : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
  }
  function color(o, u) {
    if (o.colors === "hue") return hslRgb(o.hueStart + u * o.hueRange, o.sat, o.light);
    const stops = o.use3 ? [o.c1, o.c2, o.c3] : [o.c1, o.c2];
    const k = u * (stops.length - 1), i = Math.min(stops.length - 2, Math.floor(k)), f = k - i;
    const a = hexRgb(stops[i]), b = hexRgb(stops[i + 1]);
    return a.map((x, j) => x + (b[j] - x) * f);
  }

  // ImageData of all frames, stacked top to bottom
  function render(o) {
    const n = o.size, frames = Math.max(1, o.frames);
    const img = new ImageData(n, n * frames);
    for (let fr = 0; fr < frames; fr++) {
      for (let y = 0; y < n; y++) {
        for (let x = 0; x < n; x++) {
          let u = value(o, x, y, n, fr / frames);
          if (o.levels > 1) {
            const th = o.dither ? (BAYER[y & 3][x & 3] + 0.5) / 16 : 0.5;
            u = Math.min(o.levels - 1, Math.floor(u * (o.levels - 1) + th)) / (o.levels - 1);
          }
          const c = color(o, u);
          const i = ((fr * n + y) * n + x) * 4;
          img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2]; img.data[i + 3] = 255;
        }
      }
    }
    return img;
  }

  // ------------------------------------------------------------ the panel
  // onSaved(texture) is given {file, frames, length} once it's saved
  function panel(onSaved) {
    const SCALE = 8;
    const src = document.createElement("canvas");
    const view = el("canvas", { width: 32 * SCALE / 2, height: 32 * SCALE / 2, class: "tg-view",
      "aria-label": "Generated texture preview" });
    let img = null, raf = 0;
    const redraw = () => {
      img = render(opts);
      src.width = opts.size; src.height = opts.size * Math.max(1, opts.frames);
      src.getContext("2d").putImageData(img, 0, 0);
    };
    const tick = () => {
      raf = 0;
      if (!view.isConnected) return;
      const frames = Math.max(1, opts.frames);
      const fr = frames > 1 ? Math.floor((performance.now() / 1000 / opts.length) * frames) % frames : 0;
      const ctx = view.getContext("2d");
      ctx.imageSmoothingEnabled = false;
      ctx.clearRect(0, 0, view.width, view.height);
      // (2 x 2 copies: shows whether it tiles)
      const s = view.width / 2;
      for (let i = 0; i < 2; i++) for (let j = 0; j < 2; j++)
        ctx.drawImage(src, 0, fr * opts.size, opts.size, opts.size, i * s, j * s, s, s);
      raf = requestAnimationFrame(tick);
    };
    const changed = () => { redraw(); if (!raf) raf = requestAnimationFrame(tick); };

    const row = (label, input) => el("label", { class: "blk-field" }, el("span", {}, label), input);
    const num = (key, min, max, step, fmt) => {
      const out = el("span", { class: "muted" }, fmt ? fmt(opts[key]) : String(opts[key]));
      return el("span", { class: "inline" }, el("input", { type: "range", min, max, step, value: opts[key],
        oninput: (e) => { opts[key] = +e.target.value; out.textContent = fmt ? fmt(opts[key]) : String(opts[key]); changed(); } }), out);
    };
    const col = (key) => el("input", { type: "color", value: opts[key], oninput: (e) => { opts[key] = e.target.value; changed(); } });
    const sel = (key, list, after) => el("select", { onchange: (e) => { opts[key] = isNaN(+e.target.value) ? e.target.value : +e.target.value; changed(); if (after) after(); } },
      ...list.map(([v, l]) => el("option", { value: v, selected: String(opts[key]) === String(v) || null }, l)));

    const body = el("div", { class: "tg-controls" });
    const build = () => {
      const p = opts.pattern;
      body.replaceChildren(...[
        row("Pattern", sel("pattern", PATTERNS, build)),
        row(p === "noise" ? "Size of the blobs" : "How many", num("freq", 1, 12, 0.5)),
        p === "swirl" ? row("Arms", num("arms", 1, 8, 1)) : null,
        p === "swirl" ? row("Twist", num("twist", 0, 6, 0.25)) : null,
        p === "waves" ? row("Direction", num("angle", 0, 180, 45, (v) => v + "°")) : null,
        p === "noise" ? row("Variation", el("button", { class: "small", onclick: () => { opts.seed++; changed(); } }, "Another")) : null,
        row("Colours", sel("colors", [["hue", "A cycle of hues"], ["gradient", "A gradient"]], build)),
        ...(opts.colors === "hue" ? [
          row("Starting hue", num("hueStart", 0, 359, 1, (v) => v + "°")),
          row("Hue range", num("hueRange", 0, 360, 5, (v) => v + "°")),
          row("Saturation", num("sat", 0, 100, 1, (v) => v + "%")),
          row("Lightness", num("light", 5, 95, 1, (v) => v + "%")),
        ] : [
          row("From", col("c1")), row("Through", el("span", { class: "inline" }, col("c2"),
            el("label", { class: "check" }, el("input", { type: "checkbox", checked: opts.use3 || null,
              onchange: (e) => { opts.use3 = e.target.checked; changed(); } }), " to a third:"), col("c3"))),
        ]),
        row("Shades", num("levels", 0, 16, 1, (v) => (v > 1 ? v + " shades" : "smooth"))),
        el("label", { class: "check" }, el("input", { type: "checkbox", checked: opts.dither || null,
          onchange: (e) => { opts.dither = e.target.checked; changed(); } }), " Dither between shades"),
        row("Size", sel("size", [[16, "16 × 16"], [32, "32 × 32"]])),
        row("Animation frames", num("frames", 1, 16, 1, (v) => (v > 1 ? v + " frames" : "still"))),
        row("Loop length", num("length", 0.2, 6, 0.1, (v) => (+v).toFixed(1) + " s")),
      ].filter(Boolean)); // (the options this pattern doesn't have)
    };
    build();

    const name = el("input", { type: "text", value: opts.name, oninput: (e) => { opts.name = e.target.value; } });
    const save = el("button", { class: "primary", onclick: async () => {
      redraw();
      const blob = await new Promise((res) => src.toBlob(res, "image/png"));
      try {
        const res = await api("/api/blocks/texture?name=" + encodeURIComponent((opts.name || "generated") + ".png"),
          { method: "POST", body: blob });
        const t = { file: res.file };
        if (opts.frames > 1) { t.frames = opts.frames; t.length = opts.length; }
        onSaved(t);
        toast("Saved as " + res.file + (opts.frames > 1 ? " (animated)" : ""));
      } catch (e) { toast("Not saved: " + e.message); }
    } }, "Save texture");

    changed();
    return el("div", { class: "tg" },
      el("div", { class: "tg-preview" }, view, el("small", { class: "muted" }, "Shown 2 × 2, to see how it tiles.")),
      body,
      el("div", { class: "inline" }, el("span", { class: "muted" }, "Name"), name, save));
  }

  return { panel, render };
})();
