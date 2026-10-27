// Extract sounds (the Extract sounds tab): open a long recording, mark the
// clips you want on its waveform (drag across it, or let "Find sounds"
// split it at its silences), name them, and save: each clip is cut out by
// the server (ffmpeg), with an optional short fade in and out so it
// doesn't click, and added to the sound library.
"use strict";

const Extract = (() => {
  const H = 170;          // waveform height (CSS px)
  const OVERVIEW_H = 34;  // the whole file, under it
  const EDGE_PX = 6;      // grab a clip's edge within this
  const BLOCK = 256;      // samples per precomputed peak

  let file = null;        // the File opened
  let buffer = null;      // its decoded AudioBuffer
  let mono = null;        // Float32Array, channels mixed
  let peaks = null;       // {min, max}: Float32Arrays, one per BLOCK samples
  let source = null;      // the server's id for the uploaded file (null: not sent yet)
  let clips = [];         // {name, start, end} (seconds)
  let sel = -1;
  let view = { start: 0, len: 1 }; // seconds shown
  let drag = null;
  let ctx = null, player = null, playing = null; // playing: {start, end, t0}
  let built = false;

  const opts = { folder: "", prefix: "clip", fade: true, fadeMs: 10, threshold: -40, gapMs: 200 };

  const dur = () => (buffer ? buffer.duration : 0);
  const fmt = (t) => t.toFixed(3);
  const cleanName = (s) => s.toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 80);

  // ------------------------------------------------------------ opening
  async function open(f) {
    if (clips.length && !confirm("Open another file? The clips marked on this one are dropped.")) return;
    try {
      ctx = ctx || new AudioContext();
      const data = await f.arrayBuffer();
      buffer = await ctx.decodeAudioData(data.slice(0));
    } catch (e) {
      toast("Couldn't read that file as audio: " + e.message);
      return;
    }
    file = f;
    source = null;
    clips = [];
    sel = -1;
    opts.prefix = cleanName(f.name.replace(/\.[^.]*$/, "")) || "clip";
    const n = buffer.length, ch = buffer.numberOfChannels;
    mono = new Float32Array(n);
    for (let c = 0; c < ch; c++) {
      const d = buffer.getChannelData(c);
      for (let i = 0; i < n; i++) mono[i] += d[i] / ch;
    }
    const nb = Math.ceil(n / BLOCK);
    peaks = { min: new Float32Array(nb), max: new Float32Array(nb) };
    for (let b = 0; b < nb; b++) {
      let lo = 0, hi = 0;
      for (let i = b * BLOCK, e = Math.min(n, i + BLOCK); i < e; i++) {
        const v = mono[i];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      peaks.min[b] = lo;
      peaks.max[b] = hi;
    }
    view = { start: 0, len: dur() };
    render();
  }

  // ------------------------------------------------------------ finding sounds
  // Sounds are where the level stays above the threshold; quieter stretches
  // of at least gapMs separate them. Each gets a little lead-in and tail.
  function findSounds() {
    if (!buffer) return;
    if (clips.length && !confirm(`Replace the ${clips.length} clip(s) marked with the sounds found?`)) return;
    const rate = buffer.sampleRate, win = Math.max(1, Math.round(rate * 0.01));
    const thr = Math.pow(10, opts.threshold / 20);
    const loud = [];
    for (let i = 0; i < mono.length; i += win) {
      let sum = 0;
      const e = Math.min(mono.length, i + win);
      for (let j = i; j < e; j++) sum += mono[j] * mono[j];
      loud.push(Math.sqrt(sum / (e - i)) >= thr);
    }
    const gapWins = Math.max(1, Math.round(opts.gapMs / 10));
    const found = [];
    let start = -1, quiet = 0;
    for (let w = 0; w <= loud.length; w++) {
      if (w < loud.length && loud[w]) {
        if (start < 0) start = w;
        quiet = 0;
      } else if (start >= 0) {
        quiet++;
        if (quiet >= gapWins || w === loud.length) {
          found.push([start, w - quiet + 1]);
          start = -1;
          quiet = 0;
        }
      }
    }
    const pad = 0.03;
    clips = found
      .map(([a, b]) => ({ start: Math.max(0, a * 0.01 - pad), end: Math.min(dur(), b * 0.01 + pad) }))
      .filter((c) => c.end - c.start >= 0.06);
    clips.forEach((c, i) => (c.name = numbered(i + 1)));
    sel = clips.length ? 0 : -1;
    render();
    toast(clips.length ? `Found ${clips.length} sound(s)` : "Nothing louder than the threshold: try a lower one");
  }

  function numbered(i) {
    return `${opts.prefix}_${String(i).padStart(2, "0")}`.slice(0, 80);
  }

  function nextName() {
    const taken = new Set(clips.map((c) => c.name));
    let i = clips.length + 1;
    while (taken.has(numbered(i))) i++;
    return numbered(i);
  }

  // ------------------------------------------------------------ playing
  function stop() {
    if (player) { try { player.stop(); } catch (e) { /* (already stopped) */ } }
    player = null;
    playing = null;
  }

  // a stretch of the file, faded as it will be saved
  function playRange(start, end) {
    if (!buffer) return;
    stop();
    ctx.resume();
    const src = ctx.createBufferSource();
    src.buffer = buffer;
    const gain = ctx.createGain();
    src.connect(gain).connect(ctx.destination);
    const len = end - start, now = ctx.currentTime;
    const f = opts.fade ? Math.min(opts.fadeMs / 1000, len / 2) : 0;
    if (f > 0) {
      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(1, now + f);
      gain.gain.setValueAtTime(1, now + len - f);
      gain.gain.linearRampToValueAtTime(0, now + len);
    }
    src.start(now, start, len);
    src.onended = () => { if (player === src) { player = null; playing = null; draw(); } };
    player = src;
    playing = { start, end, t0: now };
    requestAnimationFrame(tick);
  }

  function tick() {
    if (!playing) return;
    draw();
    requestAnimationFrame(tick);
  }

  // ------------------------------------------------------------ drawing
  function canvas() { return document.getElementById("exWave"); }
  function overview() { return document.getElementById("exOverview"); }

  function sizeCanvas(c, h) {
    const w = c.clientWidth, dpr = window.devicePixelRatio || 1;
    if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) {
      c.width = Math.round(w * dpr);
      c.height = Math.round(h * dpr);
    }
    const g = c.getContext("2d");
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { g, w, h };
  }

  const css = (name) => getComputedStyle(document.body).getPropertyValue(name).trim();

  // min/max of the samples between two times
  function range(t0, t1) {
    const rate = buffer.sampleRate;
    let a = Math.max(0, Math.floor(t0 * rate)), b = Math.min(mono.length, Math.ceil(t1 * rate));
    let lo = 0, hi = 0;
    if (b - a > BLOCK * 4) {
      for (let k = Math.floor(a / BLOCK), e = Math.ceil(b / BLOCK); k < e; k++) {
        if (peaks.min[k] < lo) lo = peaks.min[k];
        if (peaks.max[k] > hi) hi = peaks.max[k];
      }
    } else {
      for (let i = a; i < b; i++) {
        if (mono[i] < lo) lo = mono[i];
        if (mono[i] > hi) hi = mono[i];
      }
    }
    return [lo, hi];
  }

  function wave(g, w, h, start, len, color) {
    g.fillStyle = color;
    const mid = h / 2;
    for (let x = 0; x < w; x++) {
      const [lo, hi] = range(start + (x / w) * len, start + ((x + 1) / w) * len);
      const y0 = mid - hi * mid * 0.95, y1 = mid - lo * mid * 0.95;
      g.fillRect(x, y0, 1, Math.max(1, y1 - y0));
    }
  }

  function draw() {
    const c = canvas();
    if (!c) return;
    const { g, w, h } = sizeCanvas(c, H);
    g.fillStyle = css("--panel");
    g.fillRect(0, 0, w, h);
    if (!buffer) {
      g.fillStyle = css("--muted");
      g.font = "13px Segoe UI, sans-serif";
      g.fillText("Open a sound file (or drop one here) to see its waveform.", 14, h / 2);
      return;
    }
    const xOf = (t) => ((t - view.start) / view.len) * w;
    clips.forEach((cl, i) => {
      const x0 = xOf(cl.start), x1 = xOf(cl.end);
      if (x1 < 0 || x0 > w) return;
      g.fillStyle = i === sel ? "rgba(224,160,32,0.28)" : "rgba(95,191,119,0.16)";
      g.fillRect(x0, 0, x1 - x0, h);
      g.fillStyle = i === sel ? css("--accent") : css("--ok");
      g.fillRect(x0, 0, 2, h);
      g.fillRect(x1 - 2, 0, 2, h);
      g.font = "11px Segoe UI, sans-serif";
      g.fillText(cl.name, Math.max(2, x0 + 4), 13);
    });
    wave(g, w, h, view.start, view.len, css("--text"));
    if (drag && drag.kind === "new") {
      const a = Math.min(drag.t0, drag.t1), b = Math.max(drag.t0, drag.t1);
      g.fillStyle = "rgba(224,160,32,0.25)";
      g.fillRect(xOf(a), 0, xOf(b) - xOf(a), h);
    }
    if (playing) {
      const t = playing.start + (ctx.currentTime - playing.t0);
      g.fillStyle = "#ff6b6b";
      g.fillRect(xOf(t), 0, 1.5, h);
    }
    // the whole file, with the part shown boxed
    const o = overview();
    const ov = sizeCanvas(o, OVERVIEW_H);
    ov.g.fillStyle = css("--panel-2");
    ov.g.fillRect(0, 0, ov.w, ov.h);
    wave(ov.g, ov.w, ov.h, 0, dur(), css("--muted"));
    ov.g.strokeStyle = css("--accent");
    ov.g.lineWidth = 1.5;
    ov.g.strokeRect((view.start / dur()) * ov.w + 0.5, 0.75, Math.max(2, (view.len / dur()) * ov.w - 1), ov.h - 1.5);
    const info = document.getElementById("exInfo");
    if (info) info.textContent = `${file.name} · ${dur().toFixed(2)} s · showing ${fmt(view.start)}–${fmt(view.start + view.len)} s`;
  }

  // ------------------------------------------------------------ mouse
  function timeAt(e) {
    const r = canvas().getBoundingClientRect();
    return view.start + ((e.clientX - r.left) / r.width) * view.len;
  }

  function edgeAt(e) {
    const r = canvas().getBoundingClientRect();
    const px = (t) => r.left + ((t - view.start) / view.len) * r.width;
    // (the selected clip's edges first, then any)
    const order = sel >= 0 ? [sel, ...clips.keys()] : [...clips.keys()];
    for (const i of order) {
      if (Math.abs(e.clientX - px(clips[i].start)) <= EDGE_PX) return { i, side: "start" };
      if (Math.abs(e.clientX - px(clips[i].end)) <= EDGE_PX) return { i, side: "end" };
    }
    return null;
  }

  function onDown(e) {
    if (!buffer || e.button !== 0) return;
    const t = timeAt(e);
    const edge = edgeAt(e);
    if (edge) {
      sel = edge.i;
      drag = { kind: "edge", ...edge };
    } else {
      drag = { kind: "new", t0: t, t1: t, x0: e.clientX };
    }
    canvas().setPointerCapture(e.pointerId);
    draw();
  }

  function onMove(e) {
    if (!buffer) return;
    if (!drag) {
      canvas().style.cursor = edgeAt(e) ? "ew-resize" : "crosshair";
      return;
    }
    const t = Math.max(0, Math.min(dur(), timeAt(e)));
    if (drag.kind === "edge") {
      const c = clips[drag.i];
      if (drag.side === "start") c.start = Math.min(t, c.end - 0.01);
      else c.end = Math.max(t, c.start + 0.01);
      renderList();
    } else {
      drag.t1 = t;
    }
    draw();
  }

  function onUp(e) {
    if (!drag) return;
    const d = drag;
    drag = null;
    if (d.kind === "new") {
      if (Math.abs(e.clientX - d.x0) < 4) {
        // a click: select (and hear) the clip under it, or play from there
        const t = timeAt(e);
        const i = clips.findIndex((c) => t >= c.start && t <= c.end);
        if (i >= 0) { sel = i; playRange(clips[i].start, clips[i].end); }
        else playRange(Math.max(0, t), Math.min(dur(), t + 3));
      } else {
        const start = Math.max(0, Math.min(d.t0, d.t1)), end = Math.min(dur(), Math.max(d.t0, d.t1));
        if (end - start >= 0.01) {
          clips.push({ name: nextName(), start, end });
          clips.sort((a, b) => a.start - b.start);
          sel = clips.findIndex((c) => c.start === start && c.end === end);
          playRange(start, end);
        }
      }
    }
    renderList();
    draw();
  }

  // the wheel zooms around the pointer; Shift + wheel (or a sideways
  // scroll) moves along
  function onWheel(e) {
    if (!buffer) return;
    e.preventDefault();
    const sideways = e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY);
    if (sideways) {
      const d = (e.shiftKey ? e.deltaY : e.deltaX) || e.deltaY;
      view.start += (d / 600) * view.len;
    } else {
      const t = timeAt(e);
      const k = Math.exp(e.deltaY * 0.0015);
      const len = Math.max(0.02, Math.min(dur(), view.len * k));
      view.start = t - ((t - view.start) / view.len) * len;
      view.len = len;
    }
    clampView();
    draw();
  }

  function clampView() {
    view.len = Math.min(view.len, dur());
    view.start = Math.max(0, Math.min(dur() - view.len, view.start));
  }

  function onOverview(e) {
    if (!buffer || (e.type === "pointermove" && !(e.buttons & 1))) return;
    const r = overview().getBoundingClientRect();
    view.start = ((e.clientX - r.left) / r.width) * dur() - view.len / 2;
    clampView();
    draw();
  }

  function zoomTo(i) {
    const c = clips[i];
    const len = Math.max(0.05, (c.end - c.start) * 1.6);
    view = { start: (c.start + c.end) / 2 - len / 2, len };
    clampView();
  }

  // ------------------------------------------------------------ saving
  async function save() {
    if (!clips.length) return;
    const names = clips.map((c) => c.name);
    const bad = names.find((n) => !/^[a-z0-9_]{1,80}$/.test(n));
    if (bad !== undefined) { toast(`"${bad}" can't be a sound name: a-z, 0-9 and _ only`); return; }
    if (new Set(names).size !== names.length) { toast("Two clips have the same name"); return; }
    const btn = document.getElementById("exSave");
    btn.disabled = true;
    try {
      if (!source) {
        const q = new URLSearchParams({ filename: file.name });
        source = (await api("/api/extract/source?" + q, { method: "POST", body: file })).source;
      }
      const send = () => api("/api/extract/save", { method: "POST", json: {
        source, folder: opts.folder, fade: opts.fade, fade_ms: opts.fadeMs,
        clips: clips.map((c) => ({ name: c.name, start: c.start, end: c.end })),
      } });
      let res;
      try {
        res = await send();
      } catch (e) {
        // (the server was restarted since: send the file again)
        if (!/gone/.test(e.message)) throw e;
        const q = new URLSearchParams({ filename: file.name });
        source = (await api("/api/extract/source?" + q, { method: "POST", body: file })).source;
        res = await send();
      }
      for (const name of res.saved) addSound(name, res.folder);
      const renamed = res.saved.filter((n, i) => n !== names[i]).length;
      toast(`Saved ${res.saved.length} sound(s) to ${res.folder || "the top folder"} of the Sound library` +
        (renamed ? ` (${renamed} renamed: the name was taken)` : ""));
    } catch (e) {
      toast("Couldn't save the clips: " + e.message);
    } finally {
      btn.disabled = false;
    }
  }

  // ------------------------------------------------------------ the page
  function renderList() {
    const list = document.getElementById("exClips");
    if (!list) return;
    list.textContent = "";
    document.getElementById("exSave").textContent = `Save ${clips.length} clip${clips.length === 1 ? "" : "s"}`;
    document.getElementById("exSave").disabled = !clips.length;
    if (!clips.length) {
      list.append(el("p", { class: "hint" }, buffer
        ? "Drag across the waveform to mark a clip, or use Find sounds."
        : ""));
      return;
    }
    clips.forEach((c, i) => {
      const num = (key) => el("input", {
        type: "number", step: "0.001", min: "0", value: fmt(c[key]), class: "ex-time",
        "aria-label": `${c.name} ${key} (seconds)`,
        onchange: (e) => {
          const v = Math.max(0, Math.min(dur(), parseFloat(e.target.value) || 0));
          c[key] = v;
          if (c.end <= c.start) { if (key === "start") c.end = Math.min(dur(), v + 0.01); else c.start = Math.max(0, v - 0.01); }
          renderList(); draw();
        },
      });
      list.append(el("div", { class: "ex-row" + (i === sel ? " sel" : ""), onclick: (e) => {
        if (e.target.closest("input,button")) return;
        sel = i; zoomTo(i); renderList(); draw();
      } },
        el("button", { class: "icon", "aria-label": "Play " + c.name, onclick: () => { sel = i; playRange(c.start, c.end); renderList(); } }, "▶"),
        el("input", { type: "text", value: c.name, class: "ex-name", "aria-label": "Name",
          onchange: (e) => { c.name = cleanName(e.target.value) || c.name; renderList(); draw(); } }),
        num("start"), el("span", { class: "muted" }, "to"), num("end"),
        el("span", { class: "muted ex-len" }, `${(c.end - c.start).toFixed(3)} s`),
        el("button", { class: "icon danger", "aria-label": "Remove " + c.name, onclick: () => {
          clips.splice(i, 1);
          if (sel >= clips.length) sel = clips.length - 1;
          renderList(); draw();
        } }, "✕")));
    });
  }

  function folderSelect() {
    return el("select", { "aria-label": "Folder to save into", onchange: (e) => (opts.folder = e.target.value) },
      ...["", ...catalog.folders].map((f) => el("option", { value: f, selected: f === opts.folder || null }, f || "(top level)")));
  }

  function numberField(label, key, attrs) {
    return el("label", { class: "check" }, label,
      el("input", Object.assign({ type: "number", value: String(opts[key]), class: "ex-num",
        onchange: (e) => { opts[key] = parseFloat(e.target.value) || 0; } }, attrs)));
  }

  function render() {
    const body = document.getElementById("extractBody");
    if (!body) return;
    if (!built) {
      built = true;
      window.addEventListener("resize", draw);
      body.addEventListener("dragover", (e) => { if (e.dataTransfer.types.includes("Files")) e.preventDefault(); });
      body.addEventListener("drop", (e) => {
        const f = e.dataTransfer.files[0];
        if (f) { e.preventDefault(); open(f); }
      });
    }
    body.textContent = "";
    const fileInput = el("input", { type: "file", accept: "audio/*", hidden: true,
      onchange: (e) => { if (e.target.files[0]) open(e.target.files[0]); e.target.value = ""; } });
    body.append(
      el("div", { class: "toolbar" },
        el("label", { class: "button" }, "Open a sound file…", fileInput),
        el("span", { class: "muted", id: "exInfo" }, buffer ? "" : "WAV, OGG, MP3, FLAC…"),
        el("span", { class: "count" }),
        el("button", { class: "primary", id: "exSave", disabled: true, onclick: save }, "Save clips")),
      el("div", { class: "toolbar" },
        el("label", { class: "check" }, "Save into", folderSelect()),
        el("label", { class: "check" }, "Name new clips",
          el("input", { type: "text", value: opts.prefix, class: "ex-name", onchange: (e) => (opts.prefix = cleanName(e.target.value) || "clip") }),
          el("span", { class: "muted" }, "_01, _02…")),
        el("label", { class: "check" },
          el("input", { type: "checkbox", checked: opts.fade || null, onchange: (e) => { opts.fade = e.target.checked; } }),
          "Fade in and out"),
        numberField("", "fadeMs", { min: "1", max: "2000", step: "1", "aria-label": "Fade length (ms)" }),
        el("span", { class: "muted" }, "ms")),
      el("canvas", { id: "exWave", class: "ex-wave", style: `height:${H}px` }),
      el("canvas", { id: "exOverview", class: "ex-overview", style: `height:${OVERVIEW_H}px` }),
      el("p", { class: "hint" }, "Drag across the waveform to mark a clip (it plays); drag a clip's edge to move it; click to hear a clip or what follows. Wheel: zoom · Shift + wheel: scroll · the strip below is the whole file (click or drag it). A click on a clip in the list zooms to it. Previews play with the fade, as the clip will be saved."),
      el("div", { class: "toolbar" },
        el("button", { onclick: findSounds, disabled: !buffer || null }, "Find sounds"),
        numberField("louder than", "threshold", { min: "-90", max: "0", step: "1", "aria-label": "Threshold (dB)" }),
        el("span", { class: "muted" }, "dB, apart by at least"),
        numberField("", "gapMs", { min: "10", max: "5000", step: "10", "aria-label": "Silence between sounds (ms)" }),
        el("span", { class: "muted" }, "ms of quiet"),
        el("button", { onclick: () => { if (clips.length && confirm("Remove every clip marked?")) { clips = []; sel = -1; renderList(); draw(); } },
          disabled: !buffer || null }, "Clear clips")),
      el("div", { class: "ex-list", id: "exClips" }));
    const c = canvas();
    c.addEventListener("pointerdown", onDown);
    c.addEventListener("pointermove", onMove);
    c.addEventListener("pointerup", onUp);
    c.addEventListener("wheel", onWheel, { passive: false });
    const o = overview();
    o.addEventListener("pointerdown", (e) => { o.setPointerCapture(e.pointerId); onOverview(e); });
    o.addEventListener("pointermove", onOverview);
    renderList();
    requestAnimationFrame(draw);
  }

  // (keys while the tab is open: Space plays the selected clip, Delete removes it)
  document.addEventListener("keydown", (e) => {
    const tab = document.getElementById("tab-extract");
    if (!tab || tab.hidden || !buffer || e.target.closest("input,select,textarea")) return;
    if (e.key === " " && sel >= 0) { e.preventDefault(); playRange(clips[sel].start, clips[sel].end); }
    if ((e.key === "Delete" || e.key === "Backspace") && sel >= 0) {
      e.preventDefault();
      clips.splice(sel, 1);
      sel = Math.min(sel, clips.length - 1);
      renderList(); draw();
    }
  });

  return { render, hasClips: () => clips.length > 0 };
})();
