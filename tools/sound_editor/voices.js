// Voice generation: Kokoro voices per speaker (run on this computer), effect
// presets, the global output rate, and the per-line Generate / Re-process
// controls in "Voices & dialogue".
// (Loaded before app.js; uses its helpers at run time.)
"use strict";

const VoiceGen = (() => {
  const RATES = [8000, 11025, 16000, 22050, 32000, 44100];
  const ACCENTS = [["", "Automatic (from the voice)"], ["en-us", "American English"], ["en-gb", "British English"]];
  let cast = { output: { rate: 11025, quality: 4 }, speakers: {}, presets: {}, lines: {} };
  let takes = {};
  let status = { kokoro: {} };
  let voices = [], voicesError = "";
  let effects = {};
  let dirty = false;
  let currentPreset = null;
  let testSource = "";
  let setupTimer = null;
  const jobs = {};          // line id -> latest job
  const seenJobs = new Set();
  const autoplay = new Set(); // jobs whose result plays as soon as it's ready
  const redraws = new Map(); // line id -> redraw its dialogue row
  let polling = false;
  let stopReason = "";
  let firstPoll = true; // an old stop reason is shown quietly, not as a toast

  // voice casting, presets and per-line choices save themselves shortly after a change
  let saveTimer = null;
  const touch = () => {
    dirty = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => save().catch((e) => toast("Couldn't save the voice settings: " + e.message)), 700);
  };

  // ---------------------------------------------------------- loading
  async function load() {
    [cast, takes, status, effects] = await Promise.all([api("/api/cast"), api("/api/takes"),
      api("/api/voice/status"), api("/api/voice/effects")]);
    cast.output = Object.assign({ rate: 11025, quality: 4 }, cast.output || {});
    cast.speakers = cast.speakers || {};
    cast.presets = cast.presets || {};
    cast.lines = cast.lines || {};
    currentPreset = Object.keys(cast.presets)[0] || null;
    if (status.kokoro.installed) loadVoices();
    poll();
  }

  async function loadVoices() {
    try {
      voices = await api("/api/kokoro/voices");
      // English first, then by language, then by name
      const rank = (v) => (v.lang === "en-us" ? 0 : v.lang === "en-gb" ? 1 : 2);
      voices.sort((a, b) => rank(a) - rank(b) || a.language.localeCompare(b.language) || a.name.localeCompare(b.name));
      voicesError = "";
    } catch (e) {
      voicesError = e.message;
    }
    render();
    redraws.forEach((f) => f());
  }

  async function refreshStatus() {
    status = await api("/api/voice/status");
    const setup = status.kokoro.setup || {};
    clearTimeout(setupTimer);
    if (setup.running) setupTimer = setTimeout(refreshStatus, 1000);
    else if (status.kokoro.installed && !voices.length) await loadVoices();
    render();
  }

  async function save() {
    if (!dirty) return;
    clearTimeout(saveTimer);
    dirty = false; // changes made while this is saving mark it again
    try {
      await api("/api/cast", { method: "PUT", json: cast });
    } catch (e) {
      dirty = true;
      throw e;
    }
  }

  // ---------------------------------------------------------- helpers
  const speakers = () => {
    const n = {};
    for (const d of catalog.dialogue) n[d.speaker] = (n[d.speaker] || 0) + 1;
    return Object.entries(n).sort((a, b) => b[1] - a[1]);
  };
  const lineCast = (d) => (cast.lines[d.id] && cast.lines[d.id].cast) || d.speaker;
  const spoken = (d) => (cast.lines[d.id] && cast.lines[d.id].spoken) || d.spoken;
  const speakerCfg = (name) => cast.speakers[name] || (cast.speakers[name] = { preset: "Plain" });
  const fmt = (n) => Number(n).toLocaleString();
  const presetEffects = (name) => ((name && cast.presets[name]) || {}).effects || [];

  // a voice is "af_heart", or a blend "af_heart*0.7+bf_emma*0.3"
  const parseVoice = (spec) => (spec ? String(spec).split("+").map((p) => {
    const [n, w] = p.split("*");
    return { n: n.trim(), w: w === undefined ? 1 : +w };
  }) : []);
  const buildVoice = (parts) => (parts.length === 1 ? parts[0].n
    : parts.map((p) => `${p.n}*${+p.w.toFixed(2)}`).join("+"));
  const voiceName = (id) => { const v = voices.find((x) => x.id === id); return v ? v.name : id; };
  function voiceLabel(spec) {
    const parts = parseVoice(spec);
    if (parts.length < 2) return parts.length ? voiceName(parts[0].n) : "";
    const total = parts.reduce((s, p) => s + p.w, 0) || 1;
    return parts.map((p) => `${voiceName(p.n)} ${Math.round(100 * p.w / total)}%`).join(" + ");
  }

  // a <select> of every Kokoro voice, grouped by language
  function voiceSelect(value, first, attrs, onchange) {
    const groups = new Map();
    for (const v of voices) {
      if (!groups.has(v.language)) groups.set(v.language, []);
      groups.get(v.language).push(v);
    }
    const sel = el("select", Object.assign({ onchange: (e) => onchange(e.target.value) }, attrs),
      el("option", { value: "" }, first),
      ...[...groups].map(([lang, list]) => el("optgroup", { label: lang },
        ...list.map((v) => el("option", { value: v.id, selected: v.id === value || null },
          `${v.name}` + (v.gender ? ` (${v.gender})` : ""))))));
    if (value && !voices.find((v) => v.id === value)) {
      sel.append(el("option", { value, selected: true }, voiceLabel(value) || value));
    }
    return sel;
  }

  // hear a voice read a short sample through an effect preset, at the output rate
  async function hear(btn, voice, speed, lang, preset, text) {
    if (!voice) return toast("Choose a voice first");
    const label = btn.textContent;
    btn.disabled = true;
    btn.textContent = "…";
    try {
      const res = await api("/api/voice/sample", { method: "POST", json: {
        voice, speed: speed || 1, lang: lang || "", text: text || "", effects: presetEffects(preset), rate: cast.output.rate } });
      playUrl(res.url, "sample");
    } catch (e) { toast(e.message); }
    btn.disabled = false;
    btn.textContent = label;
  }

  function setLine(id, key, value) {
    const ln = cast.lines[id] || (cast.lines[id] = {});
    if (value === undefined || value === null || value === "") delete ln[key]; else ln[key] = value;
    if (!Object.keys(ln).length) delete cast.lines[id];
    touch();
  }

  // a modal yes/no box; resolves true/false
  function confirmBox(title, body, okLabel) {
    return new Promise((resolve) => {
      $("#confirmTitle").textContent = title;
      $("#confirmBody").replaceChildren(...body);
      $("#confirmYes").textContent = okLabel || "OK";
      $("#confirm").hidden = false;
      const done = (v) => { $("#confirm").hidden = true; $("#confirmYes").onclick = $("#confirmNo").onclick = null; resolve(v); };
      $("#confirmYes").onclick = () => done(true);
      $("#confirmNo").onclick = () => done(false);
      $("#confirmYes").focus();
    });
  }

  // ---------------------------------------------------------- jobs
  async function queue(items, play) {
    if (!items.length) return;
    try {
      await save();
      const res = await api("/api/voice/queue", { method: "POST", json: { items } });
      if (play) res.jobs.forEach((j) => autoplay.add(j));
      items.forEach((it, i) => {
        jobs[it.line] = { job: res.jobs[i], status: "queued", action: it.action };
        redrawLine(it.line);
      });
      stopReason = "";
      poll();
    } catch (e) { toast(e.message); }
  }

  function redrawLine(id) {
    const f = redraws.get(id);
    if (f) f();
  }

  async function poll() {
    if (polling) return;
    polling = true;
    try {
      for (;;) {
        const st = await api("/api/voice/jobs");
        let active = 0, changed = false;
        for (const j of st.jobs) {
          const prev = jobs[j.line];
          if (!prev || prev.job <= j.job) jobs[j.line] = j;
          if (j.status === "queued" || j.status === "running") active++;
          if ((j.status === "done" || j.status === "error" || j.status === "cancelled") && !seenJobs.has(j.job)) {
            seenJobs.add(j.job);
            changed = true;
            if (j.status === "done" && j.result && j.result.pending && autoplay.has(j.job)) {
              playUrl(j.result.pending.url, "result");
            }
            autoplay.delete(j.job);
          }
          if (prev && prev.status !== j.status) redrawLine(j.line);
        }
        if (changed) {
          takes = await api("/api/takes");
          for (const j of st.jobs) if (seenJobs.has(j.job)) redrawLine(j.line);
        }
        if (st.stopped && st.stopped !== stopReason) {
          stopReason = st.stopped;
          if (!firstPoll) toast("Stopped: " + st.stopped);
        }
        firstPoll = false;
        renderProgress(st.jobs);
        if (!active) break;
        await new Promise((r) => setTimeout(r, 900));
      }
    } catch (e) {
      toast("Lost contact with the editor server: " + e.message);
    }
    polling = false;
    renderVoicesCount();
  }

  function renderVoicesCount() {
    if (typeof renderVoices === "function" && !document.activeElement.closest(".spoken")) {
      const voiced = catalog.dialogue.filter((d) => config.voices[d.id]).length;
      const c = $("#voiceCount");
      if (c) c.textContent = c.textContent.replace(/· \d+ of/, `· ${voiced} of`);
    }
  }

  function renderProgress(list) {
    const box = $("#voiceJobs");
    if (!box) return;
    const counts = { queued: 0, running: 0, done: 0, error: 0 };
    for (const j of list) counts[j.status] = (counts[j.status] || 0) + 1;
    const total = counts.queued + counts.running + counts.done + counts.error;
    if (!counts.queued && !counts.running) {
      box.hidden = !counts.error && !stopReason;
      box.replaceChildren(el("span", {}, counts.error ? `${counts.error} line(s) failed — see the red notes on them.` : ""),
        stopReason ? el("span", { class: "err" }, " " + stopReason) : null);
      return;
    }
    box.hidden = false;
    const pct = total ? Math.round(100 * (counts.done + counts.error) / total) : 0;
    box.replaceChildren(
      el("span", {}, `Generating voices: ${counts.done + counts.error} of ${total}` + (counts.error ? ` (${counts.error} failed)` : "")),
      el("progress", { max: 100, value: pct }),
      el("button", { onclick: async () => { await api("/api/voice/cancel", { method: "POST", json: {} }); toast("Cancelled the remaining lines"); } }, "Cancel the rest"));
  }

  async function bulk(action, lines) {
    if (action === "generate") lines = lines.filter((d) => !config.voices[d.id]);
    else lines = lines.filter((d) => takes[d.id] && takes[d.id].takes.length);
    if (!lines.length) return toast(action === "generate" ? "Every shown line is voiced already" : "None of the shown lines has a take yet");
    if (action === "process") {
      const ok = await confirmBox("Re-process lines", [el("p", {},
        `Run ${lines.length} line(s) through their effects again, at the current output rate. ` +
        "Each result waits for you to listen and confirm it (filter: Awaiting review).")], "Re-process");
      if (ok) queue(lines.map((d) => ({ line: d.id, action })));
      return;
    }
    await save();
    let plan;
    try { plan = await api("/api/voice/plan", { method: "POST", json: { lines: lines.map((d) => d.id) } }); } catch (e) { return toast(e.message); }
    const ready = plan.filter((p) => p.voice && p.chars > 0);
    const missing = {};
    for (const p of plan) if (!p.voice) missing[p.speaker] = (missing[p.speaker] || 0) + 1;
    const chars = ready.reduce((n, p) => n + p.chars, 0);
    // Kokoro reads roughly 15 characters a second of speech, about 5x faster than real time on a CPU
    const minutes = Math.max(1, Math.round(chars / 15 / 5 / 60));
    const body = [el("p", {}, `${ready.length} line(s), ${fmt(chars)} characters — roughly ${minutes} minute(s) on this computer.`),
      el("p", { class: "muted" }, "Nothing is saved to the game until you confirm it: listen to each result with the “Awaiting review” filter.")];
    if (Object.keys(missing).length) {
      body.push(el("p", { class: "warnline" }, "Skipped (no voice chosen in Voice casting): " +
        Object.entries(missing).map(([s, n]) => `${s} (${n})`).join(", ")));
    }
    if (!ready.length) return confirmBox("Nothing to generate", body, "OK");
    if (await confirmBox("Generate voices", body, `Generate ${ready.length} line(s)`)) {
      queue(ready.map((p) => ({ line: p.line, action: "generate" })));
    }
  }

  // ---------------------------------------------------------- dialogue rows
  // what this line will be read with: its own choices, else its speaker's
  const NO_EFFECTS = "__none__";
  function planFor(d) {
    const ln = cast.lines[d.id] || {};
    const sc = cast.speakers[lineCast(d)] || {};
    let preset = "preset" in ln ? ln.preset : (sc.preset || "");
    if (preset === NO_EFFECTS) preset = "";
    const voice = ln.voice || sc.voice || "";
    return { voice, speed: ln.speed || sc.speed || 1, lang: ln.voice ? "" : (sc.lang || ""), preset };
  }

  // Generate -> listen to the processed result -> Confirm (or Regenerate)
  function rowControls(d, redraw) {
    redraws.set(d.id, redraw);
    const box = el("div", { class: "gen" });
    const t = takes[d.id];
    const job = jobs[d.id];
    const ln = cast.lines[d.id] || {};
    const sc = cast.speakers[lineCast(d)] || {};
    const plan = planFor(d);
    const busy = job && (job.status === "queued" || job.status === "running");
    const hasTake = t && t.takes.length;
    const pending = t && t.pending;
    const ready = status.kokoro.installed;

    // voice and effect for this line
    const voiceSel = voiceSelect(ln.voice || "",
      sc.voice ? `${lineCast(d)}'s voice: ${voiceLabel(sc.voice)}` : (ready ? "— choose a voice —" : "Install Kokoro in Voice casting"),
      { "aria-label": "Voice for this line", disabled: busy || null },
      (v) => { setLine(d.id, "voice", v); redrawLine(d.id); });
    const hearBtn = el("button", { class: "icon", "aria-label": "Hear this voice", title: "Hear this voice read the line, with its effect",
      disabled: !plan.voice || !ready || null,
      onclick: () => hear(hearBtn, plan.voice, plan.speed, plan.lang, plan.preset, spoken(d)) }, "▶");
    const effectSel = el("select", { "aria-label": "Effect for this line", disabled: busy || null, onchange: (e) => {
      setLine(d.id, "preset", e.target.value);
      // a new effect on the same take is quick: preview it straight away
      if (hasTake) queue([{ line: d.id, action: "process" }], true);
      else redrawLine(d.id);
    } }, el("option", { value: "" }, `${lineCast(d)}'s effect: ${sc.preset || "none"}`),
    el("option", { value: NO_EFFECTS, selected: ln.preset === NO_EFFECTS || null }, "No effects"),
    ...Object.keys(cast.presets).map((p) => el("option", { value: p, selected: (ln.preset === p) || null }, p)));
    box.append(el("div", { class: "genpick" },
      el("label", {}, el("span", {}, "Voice"), el("div", { class: "with-play" }, voiceSel, hearBtn)),
      el("label", {}, el("span", {}, "Effect"), effectSel)));

    // generate
    const words = /\p{L}/u.test(spoken(d));
    box.append(el("button", {
      class: (pending ? "" : "primary ") + "small", disabled: busy || !plan.voice || !words || !ready || null,
      title: !words ? "Nothing to read: this line is only placeholders. Write what should be said in Spoken text."
        : !ready ? "Install Kokoro in Voice casting first"
          : plan.voice ? `Reads the spoken text with ${voiceLabel(plan.voice)}` : "Choose a voice first",
      onclick: () => queue([{ line: d.id, action: "generate" }], true),
    }, pending ? "↻ Regenerate" : "Generate"));
    if (!words) box.append(el("div", { class: "jobnote error" }, "Only placeholders: write its Spoken text to voice it."));

    if (job && job.status !== "done") {
      const label = { queued: "Waiting…", running: job.action === "process" ? "Applying the effects…" : "Reading it with Kokoro…",
        error: job.message, cancelled: "Cancelled" }[job.status] || job.status;
      box.append(el("div", { class: "jobnote " + job.status }, label));
    }

    // review the result
    if (pending && !busy) {
      const k = t.takes[pending.take] || {};
      box.append(el("div", { class: "review" },
        el("div", { class: "review-head" },
          el("button", { class: "primary small", onclick: () => playUrl(pending.url) }, "▶ Play result"),
          el("span", { class: "muted" }, `${k.voice || pending.voice} · ${pending.preset || "no effects"} · ${(pending.rate / 1000).toLocaleString()} kHz`)),
        el("div", { class: "review-actions" },
          el("button", { class: "small ok", onclick: () => confirmLine(d) }, "✓ Confirm"),
          el("button", { class: "small", onclick: () => queue([{ line: d.id, action: "generate" }], true) }, "↻ Regenerate"),
          el("button", { class: "small", onclick: () => discardLine(d) }, "Discard"))));
    }

    // earlier takes can be previewed again
    if (hasTake && !busy) {
      const cur = t.current || 0;
      box.append(el("details", { class: "older" }, el("summary", {}, `Takes (${t.takes.length})`),
        el("div", { class: "takes" },
          el("select", { "aria-label": "Take", onchange: async (e) => {
            try {
              await api("/api/voice/take", { method: "POST", json: { line: d.id, index: +e.target.value } });
              t.current = +e.target.value;
              queue([{ line: d.id, action: "process" }], true);
            } catch (err) { toast(err.message); }
          } }, ...t.takes.map((x, i) => el("option", { value: i, selected: i === cur || null },
            `Take ${i + 1} · ${x.voice} · ${new Date(x.time * 1000).toLocaleString()}`))),
          el("button", { class: "icon", title: "Play this take as it was read (no effects, full quality)",
            onclick: () => playUrl("/takes/" + encodeURI(t.takes[cur].file)) }, "▶ raw"))));
    }
    return box;
  }

  async function confirmLine(d) {
    try {
      const res = await api("/api/voice/confirm", { method: "POST", json: { line: d.id } });
      const old = config.voices[d.id] || {};
      config.voices[d.id] = { sound: res.sound, volume: old.volume ?? 100 };
      addSound(res.sound, "voices");
      if (takes[d.id]) delete takes[d.id].pending;
      redrawLine(d.id);
      renderVoicesCount();
      toast("Saved — the game uses it from now on");
    } catch (e) { toast(e.message); }
  }

  async function discardLine(d) {
    try {
      await api("/api/voice/discard", { method: "POST", json: { line: d.id } });
      if (takes[d.id]) delete takes[d.id].pending;
      redrawLine(d.id);
    } catch (e) { toast(e.message); }
  }

  function spokenEditor(d) {
    const ln = cast.lines[d.id] || {};
    const edited = !!ln.spoken;
    const det = el("details", { class: "spoken" });
    const summary = el("summary", {}, "Spoken text" + (edited ? " (edited)" : ""),
      d.varies && d.varies.length && !edited ? el("span", { class: "varies" }, "changes in play: " + d.varies.join(", ")) : null,
      ln.cast ? el("span", { class: "castas" }, "voiced as " + ln.cast) : null);
    const ta = el("textarea", { rows: Math.min(10, Math.max(2, Math.ceil(spoken(d).length / 80))),
      "aria-label": "Text sent to the voice generator",
      oninput: (e) => { setLine(d.id, "spoken", e.target.value === d.spoken ? "" : e.target.value); } });
    ta.value = spoken(d);
    const castSel = el("select", { "aria-label": "Voice this line as", onchange: (e) => {
      setLine(d.id, "cast", e.target.value === d.speaker ? "" : e.target.value);
      redrawLine(d.id);
    } }, ...speakers().map(([s]) => el("option", { value: s, selected: s === lineCast(d) || null }, s)));
    det.append(summary, ta, el("div", { class: "spoken-tools" },
      el("label", {}, "Voice as ", castSel),
      el("button", { class: "small", onclick: () => { setLine(d.id, "spoken", ""); ta.value = d.spoken; } }, "Reset text"),
      el("span", { class: "muted" }, `${spoken(d).length} characters`)));
    if (d.varies && d.varies.length) {
      det.append(el("p", { class: "muted" }, "This line has parts that change from game to game (" + d.varies.join(", ") +
        "). The recording can't change with them, so they are read generically — edit the text if you'd rather word it differently."));
    }
    return det;
  }

  // ---------------------------------------------------------- casting tab
  function render() {
    const root = $("#castingBody");
    if (!root) return;
    root.replaceChildren(setupSection(), speakersSection(), presetsSection());
  }

  function card(title, ok, ...kids) {
    return el("div", { class: "setup-card" + (ok ? " ok" : "") },
      el("h3", {}, el("span", { class: "dot", "aria-hidden": "true" }), title), ...kids);
  }

  function setupSection() {
    const k = status.kokoro || {};
    const setup = k.setup || {};
    let body;
    if (setup.running) {
      body = [el("p", {}, setup.step + "…"),
        setup.step.startsWith("Downloading") ? el("progress", { max: 1, value: setup.progress || 0 }) : el("progress", {})];
    } else if (k.installed) {
      body = [el("p", {}, "Kokoro reads the lines on this computer: no account, no credits, nothing is sent online."),
        voicesError ? el("p", { class: "err" }, voicesError) : el("p", { class: "muted" }, `${voices.length} voices. Blend two in a speaker's Voice settings for something in between.`),
        el("button", { onclick: loadVoices }, "Reload voices")];
    } else {
      body = [el("p", {}, "Kokoro is a small text-to-speech model that runs on this computer. Installing it makes a Python environment in ",
        el("code", {}, "voice_work/kokoro"), " (kokoro-onnx and onnxruntime) and downloads the model, about 120 MB, once."),
      setup.error ? el("p", { class: "err" }, setup.error) : null,
      el("button", { class: "primary", onclick: async () => {
        try { status.kokoro = await api("/api/kokoro/setup", { method: "POST", json: {} }); } catch (e) { return toast(e.message); }
        refreshStatus();
      } }, setup.error ? "Try again" : "Install Kokoro")];
    }
    const kokoro = card("Kokoro", k.installed && !voicesError, ...body);
    const rate = el("select", { "aria-label": "Sample rate", onchange: (e) => { cast.output.rate = +e.target.value; touch(); render(); } },
      ...RATES.map((r) => el("option", { value: r, selected: r === +cast.output.rate || null }, `${fmt(r)} Hz` + (r === 11025 ? " (default, lo-fi)" : ""))));
    const q = el("input", { type: "range", min: 0, max: 10, value: cast.output.quality ?? 4, "aria-label": "Ogg quality",
      oninput: (e) => { cast.output.quality = +e.target.value; qv.textContent = e.target.value; touch(); } });
    const qv = el("span", {}, String(cast.output.quality ?? 4));
    const out = card("Output", status.ffmpeg,
      el("p", {}, "The global rate: after its effects, every voice line is resampled to this rate and saved as Ogg in ",
        el("code", {}, "sounds/voices"), ". A change applies to lines generated or re-processed from then on."),
      el("div", { class: "inline" }, el("label", {}, "Sample rate ", rate), el("label", {}, "Ogg quality ", q, qv)),
      status.ffmpeg ? null : el("p", { class: "err" }, "ffmpeg wasn't found on PATH; it's needed for effects and to convert files."));
    return el("section", { class: "cast-sec" }, el("h2", {}, "Setup"), el("div", { class: "setup" }, kokoro, out));
  }

  function slider(label, value, min, max, step, unit, onInput) {
    const show = (v) => `${+(+v).toFixed(2)}${unit || ""}`;
    const out = el("span", {}, show(value));
    return el("label", { class: "sl" }, el("span", {}, label), el("input", { type: "range", min, max, step, value,
      oninput: (e) => { out.textContent = show(e.target.value); onInput(+e.target.value); } }), out);
  }

  function speakersSection() {
    const rows = [];
    const ready = status.kokoro.installed;
    for (const [name] of speakers()) {
      const sc = speakerCfg(name);
      const lines = catalog.dialogue.filter((d) => lineCast(d) === name);
      const voiced = lines.filter((d) => config.voices[d.id]).length;
      const parts = parseVoice(sc.voice);
      const setVoice = (p) => { sc.voice = p.length ? buildVoice(p) : undefined; touch(); render(); };
      const main = voiceSelect(parts[0] ? parts[0].n : "", ready ? "— choose a voice —" : "— install Kokoro —",
        { "aria-label": "Voice for " + name }, (v) => {
          if (!v) return setVoice([]);
          setVoice(parts.length > 1 ? [{ n: v, w: parts[0].w }, ...parts.slice(1)] : [{ n: v, w: 1 }]);
        });
      const blend = voiceSelect(parts[1] ? parts[1].n : "", "No blend", { "aria-label": "Blend with", disabled: !parts.length || null },
        (v) => {
          if (!v) return setVoice(parts.slice(0, 1).map((p) => ({ n: p.n, w: 1 })));
          const mix = parts[1] ? parts[1].w / (parts[0].w + parts[1].w) : 0.3;
          setVoice([{ n: parts[0].n, w: 1 - mix }, { n: v, w: mix }]);
        });
      const hearBtn = el("button", { class: "icon", "aria-label": "Hear " + name, title: "Hear this voice, with the speaker's effect",
        disabled: !sc.voice || !ready || null, onclick: () => hear(hearBtn, sc.voice, sc.speed, sc.lang, sc.preset) }, "▶");
      const presetSel = el("select", { "aria-label": "Effect preset for " + name, onchange: (e) => { sc.preset = e.target.value; touch(); } },
        el("option", { value: "" }, "No effects"),
        ...Object.keys(cast.presets).map((p) => el("option", { value: p, selected: p === sc.preset || null }, p)));
      const settings = el("details", { class: "spk-set" }, el("summary", {}, "Voice settings"),
        slider("Speed", sc.speed || 1, 0.5, 2, 0.05, "×", (v) => { sc.speed = v === 1 ? undefined : v; touch(); }),
        parts.length > 1 ? slider("Blend", Math.round(100 * parts[1].w / (parts[0].w + parts[1].w)), 5, 95, 5, "%",
          (v) => { sc.voice = buildVoice([{ n: parts[0].n, w: (100 - v) / 100 }, { n: parts[1].n, w: v / 100 }]); touch(); }) : null,
        el("label", { class: "sl" }, el("span", {}, "Accent"), el("select", { onchange: (e) => { sc.lang = e.target.value || undefined; touch(); } },
          ...ACCENTS.map(([v, l]) => el("option", { value: v, selected: v === (sc.lang || "") || null }, l)))));
      const unvoiced = lines.length - voiced;
      rows.push(el("div", { class: "spk" + (sc.voice ? " cast" : "") },
        el("div", { class: "spk-name" }, el("b", {}, name), el("div", { class: "muted" }, `${voiced} of ${lines.length} lines voiced`)),
        el("div", { class: "spk-voice" }, main, hearBtn), blend, presetSel, settings,
        el("button", { class: "small", disabled: !sc.voice || !unvoiced || !ready || null,
          onclick: () => bulk("generate", lines) }, unvoiced ? `Generate ${unvoiced} unvoiced` : "All voiced")));
    }
    return el("section", { class: "cast-sec" }, el("h2", {}, "Speakers"),
      el("p", { class: "hint" }, "Choose a Kokoro voice for each speaker (optionally blended with a second one), and an effect preset. " +
        "Voice settings has the speed and the blend's mix. ▶ plays a sample with the effect, at the output rate. " +
        "A single line can be voiced as another speaker from its Spoken text panel."),
      el("div", { class: "spk-list" }, ...rows));
  }

  // ------------------------------------------- presets
  function presetsSection() {
    const names = Object.keys(cast.presets);
    if (currentPreset && !cast.presets[currentPreset]) currentPreset = names[0] || null;
    const list = el("div", { class: "preset-list" },
      ...names.map((n) => el("button", { class: "folder", "aria-pressed": String(n === currentPreset),
        onclick: () => { currentPreset = n; render(); } }, n)),
      el("button", { class: "add", onclick: () => {
        const n = prompt("Name for the new preset");
        if (!n || cast.presets[n]) return;
        cast.presets[n] = { effects: [] }; currentPreset = n; touch(); render();
      } }, "+ New preset"));
    const sec = el("section", { class: "cast-sec" }, el("h2", {}, "Effect presets"),
      el("p", { class: "hint" }, "A preset is a chain of effects, applied to the whole take in order. Give each speaker (or a single line) the preset that suits it. Resampling to the output rate always happens last."));
    sec.append(el("div", { class: "presets" }, list, currentPreset ? presetEditor(currentPreset) : el("p", { class: "muted" }, "No presets yet.")));
    return sec;
  }

  function newEffect(type) {
    const fx = { type };
    for (const p of effects[type].params) fx[p.key] = p.default;
    return fx;
  }

  function paramFields(fx) {
    const def = effects[fx.type];
    const box = el("div", { class: "params" });
    for (const p of def.params) {
      const cur = fx[p.key] ?? p.default;
      if (p.type === "bool") {
        box.append(el("label", { class: "check" }, el("input", { type: "checkbox", checked: !!+cur || null,
          onchange: (e) => { fx[p.key] = e.target.checked ? 1 : 0; touch(); } }), p.label));
      } else if (p.type === "choice") {
        box.append(el("label", { class: "sl" }, el("span", {}, p.label), el("select", { onchange: (e) => { fx[p.key] = +e.target.value; touch(); } },
          ...p.choices.map((c) => el("option", { value: c, selected: +c === +cur || null }, String(c))))));
      } else {
        box.append(slider(p.label, cur, p.min, p.max, p.step, p.unit ? " " + p.unit : "", (v) => { fx[p.key] = v; touch(); }));
      }
    }
    return box;
  }

  function presetEditor(name) {
    const preset = cast.presets[name];
    const list = preset.effects || (preset.effects = []);
    const box = el("div", { class: "preset-ed" });
    const redraw = () => render();
    const types = Object.entries(effects).sort((a, b) => a[1].name.localeCompare(b[1].name));
    const rows = list.map((fx, i) => {
      const def = effects[fx.type];
      if (!def) {
        return el("div", { class: "fx off" }, el("div", { class: "fx-head" }, el("span", { class: "num" }, String(i + 1)),
          el("span", { class: "muted" }, `Unknown effect “${fx.type}”`),
          el("button", { class: "icon", "aria-label": "Remove effect", onclick: () => { list.splice(i, 1); touch(); redraw(); } }, "✕")));
      }
      const typeSel = el("select", { "aria-label": `Effect ${i + 1}`, onchange: (e) => { list[i] = newEffect(e.target.value); touch(); redraw(); } },
        ...types.map(([id, d]) => el("option", { value: id, selected: id === fx.type || null }, d.name)));
      return el("div", { class: "fx" + (fx.off ? " off" : "") },
        el("div", { class: "fx-head" },
          el("span", { class: "num" }, String(i + 1)),
          el("input", { type: "checkbox", title: "On / off", "aria-label": "Effect on", checked: !fx.off || null,
            onchange: (e) => { if (e.target.checked) delete fx.off; else fx.off = true; touch(); redraw(); } }),
          typeSel,
          el("button", { class: "icon", "aria-label": "Move up", disabled: i === 0 || null, onclick: () => { [list[i - 1], list[i]] = [list[i], list[i - 1]]; touch(); redraw(); } }, "↑"),
          el("button", { class: "icon", "aria-label": "Move down", disabled: i === list.length - 1 || null, onclick: () => { [list[i + 1], list[i]] = [list[i], list[i + 1]]; touch(); redraw(); } }, "↓"),
          el("button", { class: "icon", "aria-label": "Remove effect", onclick: () => { list.splice(i, 1); touch(); redraw(); } }, "✕")),
        el("div", { class: "fx-tip" }, def.tip),
        paramFields(fx));
    });
    const addSel = el("select", { "aria-label": "Add an effect", onchange: (e) => {
      if (!effects[e.target.value]) return;
      list.push(newEffect(e.target.value));
      touch(); redraw();
    } }, el("option", { value: "" }, "+ Add an effect…"), ...types.map(([id, d]) => el("option", { value: id }, d.name)));

    // test the preset: on a speaker's voice, a take, or any sound
    const sources = [];
    for (const [s] of speakers()) if (cast.speakers[s] && cast.speakers[s].voice) sources.push(["speaker:" + s, `Voice: ${s} (${voiceLabel(cast.speakers[s].voice)})`]);
    for (const d of catalog.dialogue) if (takes[d.id] && takes[d.id].takes.length) sources.push(["take:" + d.id, "Take: " + d.id]);
    for (const s of catalog.sounds) sources.push(["sound:" + s.name, "Sound: " + (s.folder ? s.folder + "/" : "") + s.name]);
    if ((!testSource || !sources.find(([v]) => v === testSource)) && sources.length) testSource = sources[0][0];
    const srcSel = el("select", { "aria-label": "Audio to test the preset on", onchange: (e) => { testSource = e.target.value; } },
      ...sources.slice(0, 1500).map(([v, l]) => el("option", { value: v, selected: v === testSource || null }, l)));
    const test = el("button", { class: "primary small", disabled: !status.ffmpeg || null, onclick: async () => {
      if (testSource.startsWith("speaker:")) {
        const sc = cast.speakers[testSource.slice(8)];
        test.disabled = true;
        try {
          const res = await api("/api/voice/sample", { method: "POST", json: {
            voice: sc.voice, speed: sc.speed || 1, lang: sc.lang || "", effects: list, rate: cast.output.rate } });
          playUrl(res.url, "preview");
        } catch (e) { toast(e.message); }
        test.disabled = false;
        return;
      }
      test.disabled = true; test.textContent = "Processing…";
      try {
        const res = await api("/api/voice/preview", { method: "POST", json: { effects: list, rate: cast.output.rate, source: testSource } });
        playUrl(res.url, "preview");
      } catch (e) { toast(e.message); }
      test.disabled = false; test.textContent = "▶ Test preset";
    } }, "▶ Test preset");

    box.append(
      el("div", { class: "preset-head" }, el("h3", {}, name),
        el("button", { class: "small", onclick: () => {
          const n = prompt("Rename preset", name);
          if (!n || n === name || cast.presets[n]) return;
          cast.presets[n] = preset; delete cast.presets[name];
          for (const sc of Object.values(cast.speakers)) if (sc.preset === name) sc.preset = n;
          for (const ln of Object.values(cast.lines)) if (ln.preset === name) ln.preset = n;
          currentPreset = n; touch(); redraw();
        } }, "Rename"),
        el("button", { class: "small", onclick: () => {
          let n = name + " copy", k = 2;
          while (cast.presets[n]) n = `${name} copy ${k++}`;
          cast.presets[n] = JSON.parse(JSON.stringify(preset)); currentPreset = n; touch(); redraw();
        } }, "Duplicate"),
        el("button", { class: "small", onclick: () => {
          if (!confirm(`Delete the preset "${name}"?`)) return;
          delete cast.presets[name];
          for (const sc of Object.values(cast.speakers)) if (sc.preset === name) sc.preset = "";
          for (const ln of Object.values(cast.lines)) if (ln.preset === name) delete ln.preset;
          touch(); redraw();
        } }, "Delete")),
      el("div", { class: "steps" }, ...(rows.length ? rows : [el("p", { class: "muted" }, "No effects: the take is only resampled.")])),
      el("div", { class: "inline" }, addSel),
      el("div", { class: "step final" }, el("span", { class: "num" }, "∎"),
        el("span", { class: "muted" }, `Resample to ${fmt(cast.output.rate)} Hz (the output rate) → Ogg`)),
      el("div", { class: "inline test" }, el("span", {}, "Test on"), srcSel, test),
      el("p", { class: "hint" }, "After changing a preset, use Re-process on lines (or “Re-process shown lines” in Voices & dialogue) to apply it to takes already made."));
    return box;
  }

  return { load, save, render, rowControls, spokenEditor, bulk, isDirty: () => dirty,
    awaitingReview: (id) => !!(takes[id] && takes[id].pending) };
})();
