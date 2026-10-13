// Voice generation: ElevenLabs voices per speaker, Tenacity effect presets,
// and the per-line Generate / Re-process controls in "Voices & dialogue".
// (Loaded before app.js; uses its helpers at run time.)
"use strict";

const VoiceGen = (() => {
  const RATES = [8000, 11025, 16000, 22050, 32000, 44100];
  const DEFAULT_SETTINGS = { stability: 0.5, similarity_boost: 0.75, style: 0, speed: 1, use_speaker_boost: true };
  let cast = { output: { rate: 11025, quality: 4 }, speakers: {}, presets: {}, lines: {} };
  let takes = {};
  let status = {};
  let voices = [], models = [], subscription = null, elevenError = "";
  let commands = null, macros = {};
  let dirty = false;
  let currentPreset = null;
  let testSource = "";
  const jobs = {};          // line id -> latest job
  const seenJobs = new Set();
  const redraws = new Map(); // line id -> redraw its dialogue row
  let polling = false;
  let stopReason = "";
  let firstPoll = true; // an old stop reason is shown quietly, not as a toast

  const touch = () => { dirty = true; markDirty(); };

  // ---------------------------------------------------------- loading
  async function load() {
    [cast, takes, status] = await Promise.all([api("/api/cast"), api("/api/takes"), api("/api/voice/status")]);
    cast.output = Object.assign({ rate: 11025, quality: 4 }, cast.output || {});
    cast.speakers = cast.speakers || {};
    cast.presets = cast.presets || {};
    cast.lines = cast.lines || {};
    currentPreset = Object.keys(cast.presets)[0] || null;
    if (status.key) loadEleven();
    if (status.tenacity) loadTenacity();
    poll();
  }

  async function loadEleven() {
    try {
      [voices, models, subscription] = await Promise.all([
        api("/api/eleven/voices"), api("/api/eleven/models"), api("/api/eleven/subscription")]);
      voices.sort((a, b) => a.name.localeCompare(b.name));
      elevenError = "";
    } catch (e) {
      elevenError = e.message;
    }
    render();
  }

  async function loadTenacity() {
    try {
      [commands, macros] = await Promise.all([api("/api/tenacity/commands"), api("/api/tenacity/macros")]);
    } catch (e) {
      commands = null;
    }
    render();
  }

  async function refreshStatus() {
    status = await api("/api/voice/status");
    if (status.tenacity && !commands) await loadTenacity();
    render();
  }

  async function save() {
    if (!dirty) return;
    await api("/api/cast", { method: "PUT", json: cast });
    dirty = false;
  }

  // ---------------------------------------------------------- helpers
  const speakers = () => {
    const n = {};
    for (const d of catalog.dialogue) n[d.speaker] = (n[d.speaker] || 0) + 1;
    return Object.entries(n).sort((a, b) => b[1] - a[1]);
  };
  const lineCast = (d) => (cast.lines[d.id] && cast.lines[d.id].cast) || d.speaker;
  const spoken = (d) => (cast.lines[d.id] && cast.lines[d.id].spoken) || d.spoken;
  const speakerCfg = (name) => cast.speakers[name] || (cast.speakers[name] = { settings: Object.assign({}, DEFAULT_SETTINGS), preset: "Plain" });
  const modelCost = (id) => { const m = models.find((x) => x.model_id === id); return m ? m.cost : 1; };
  const fmt = (n) => Number(n).toLocaleString();

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

  // "Name: Key=1 Other="a b"" <-> {id, params}
  function parseStep(line) {
    const i = line.indexOf(":");
    const id = (i < 0 ? line : line.slice(0, i)).trim();
    const params = {};
    const re = /([\w-]+)=("([^"]*)"|\S+)/g;
    let m;
    while ((m = re.exec(i < 0 ? "" : line.slice(i + 1)))) params[m[1]] = m[3] !== undefined ? m[3] : m[2];
    return { id, params };
  }
  function stepText(id, params) {
    const parts = Object.entries(params).map(([k, v]) => `${k}=${/\s/.test(String(v)) ? '"' + v + '"' : v}`);
    return `${id}:` + (parts.length ? " " + parts.join(" ") : "");
  }

  // ---------------------------------------------------------- jobs
  async function queue(items) {
    if (!items.length) return;
    try {
      await save();
      const res = await api("/api/voice/queue", { method: "POST", json: { items } });
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
            if (j.status === "done" && j.result) {
              const old = config.voices[j.line] || {};
              config.voices[j.line] = { sound: j.result.sound, volume: old.volume ?? 100 };
              addSound(j.result.sound, "voices");
            }
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
        `Run ${lines.length} line(s) through their speaker's Tenacity preset again (no ElevenLabs credits are used).`)], "Re-process");
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
    const credits = Math.round(ready.reduce((n, p) => n + p.chars * modelCost(p.model), 0));
    const body = [el("p", {}, `${ready.length} line(s), ${fmt(chars)} characters — about ${fmt(credits)} ElevenLabs credits.`)];
    if (subscription && subscription.character_limit) {
      body.push(el("p", { class: "muted" }, `You have used ${fmt(subscription.character_count)} of ${fmt(subscription.character_limit)} this period.`));
    }
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
  function rowControls(d, redraw) {
    redraws.set(d.id, redraw);
    const box = el("div", { class: "gen" });
    const t = takes[d.id];
    const job = jobs[d.id];
    const sc = cast.speakers[lineCast(d)] || {};
    const busy = job && (job.status === "queued" || job.status === "running");
    const text = spoken(d);
    const credits = Math.round(text.length * modelCost(sc.model_id || "eleven_multilingual_v2"));
    const genBtn = el("button", {
      class: "primary small", disabled: busy || !sc.voice_id || null,
      title: sc.voice_id ? `About ${credits} credits` : `Choose a voice for "${lineCast(d)}" in Voice casting first`,
      onclick: () => queue([{ line: d.id, action: "generate" }]),
    }, t && t.takes.length ? "Generate again" : "Generate voice");
    box.append(genBtn);
    if (t && t.takes.length) {
      const cur = t.current || 0;
      const sel = el("select", { "aria-label": "Take", disabled: busy || null, onchange: async (e) => {
        try {
          await api("/api/voice/take", { method: "POST", json: { line: d.id, index: +e.target.value } });
          t.current = +e.target.value;
          queue([{ line: d.id, action: "process" }]);
        } catch (err) { toast(err.message); }
      } }, ...t.takes.map((k, i) => el("option", { value: i, selected: i === cur || null },
        `Take ${i + 1} · ${k.voice} · ${new Date(k.time * 1000).toLocaleDateString()}`)));
      box.append(el("div", { class: "takes" }, sel,
        el("button", { class: "icon", title: "Play the raw take (before Tenacity)", "aria-label": "Play raw take",
          onclick: () => playUrl("/takes/" + encodeURI(t.takes[cur].file)) }, "▶ raw"),
        el("button", { class: "small", disabled: busy || null, title: "Run the take through the preset again",
          onclick: () => queue([{ line: d.id, action: "process" }]) }, "Re-process")));
    }
    if (job && job.status !== "done") {
      const label = { queued: "Waiting…", running: job.action === "process" ? "Processing in Tenacity…" : "Generating…",
        error: job.message, cancelled: "Cancelled" }[job.status] || job.status;
      box.append(el("div", { class: "jobnote " + job.status }, label));
    }
    return box;
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
    const keyInput = el("input", { type: "password", placeholder: "Paste your ElevenLabs API key", autocomplete: "off", "aria-label": "ElevenLabs API key" });
    const saveKey = async () => {
      try {
        await api("/api/voice/key", { method: "PUT", json: { key: keyInput.value } });
        keyInput.value = "";
        await refreshStatus();
        if (status.key) loadEleven();
        toast(status.key ? "Key saved" : "Key removed");
      } catch (e) { toast(e.message); }
    };
    const eleven = card("ElevenLabs", status.key && !elevenError,
      status.key
        ? el("p", {}, status.key_source === "saved"
          ? `Key saved (${status.key_hint}), encrypted for your Windows account and kept outside the project.`
          : "Using the key from the ELEVENLABS_API_KEY environment variable. A key saved here takes priority over it.")
        : el("p", {}, "Paste an API key from ", el("a", { href: "https://elevenlabs.io/app/settings/api-keys", target: "_blank", rel: "noopener" }, "your ElevenLabs account"), ". It needs text-to-speech, voices and user access."),
      elevenError ? el("p", { class: "err" }, elevenError) : null,
      subscription && subscription.character_limit
        ? el("p", { class: "muted" }, `${subscription.tier || ""} plan: ${fmt(subscription.character_count)} of ${fmt(subscription.character_limit)} credits used this period.`) : null,
      status.key && !elevenError ? el("p", { class: "muted" }, `${voices.length} voices available.`) : null,
      el("div", { class: "inline" }, keyInput, el("button", { onclick: saveKey }, status.key ? "Replace key" : "Save key"),
        status.key ? el("button", { onclick: () => { keyInput.value = ""; saveKey(); } }, "Remove key") : null,
        status.key ? el("button", { onclick: loadEleven }, "Refresh voices") : null));
    const ten = card("Tenacity", status.tenacity,
      status.tenacity
        ? el("p", {}, "Connected. Keep Tenacity open while voices are generated or re-processed; it works in its current project window.")
        : el("div", {},
          el("p", {}, status.tenacity_installed ? "Tenacity is installed but isn't reachable yet. One-time setup:" : "Tenacity wasn't found in Program Files."),
          el("ol", {},
            el("li", {}, "Open Tenacity."),
            el("li", {}, "Edit › Preferences › Modules: set ", el("code", {}, "mod-script-pipe"), " to ", el("b", {}, "Enabled"), "."),
            el("li", {}, "Close and reopen Tenacity, then press Check again."))),
      el("button", { onclick: refreshStatus }, "Check again"));
    const rate = el("select", { "aria-label": "Sample rate", onchange: (e) => { cast.output.rate = +e.target.value; touch(); } },
      ...RATES.map((r) => el("option", { value: r, selected: r === +cast.output.rate || null }, `${fmt(r)} Hz` + (r === 11025 ? " (lo-fi)" : ""))));
    const q = el("input", { type: "range", min: 0, max: 10, value: cast.output.quality ?? 4, "aria-label": "Ogg quality",
      oninput: (e) => { cast.output.quality = +e.target.value; qv.textContent = e.target.value; touch(); } });
    const qv = el("span", {}, String(cast.output.quality ?? 4));
    const out = card("Output", status.ffmpeg,
      el("p", {}, "After a preset's effects, Tenacity resamples every voice line to this rate, then it's saved as Ogg in ",
        el("code", {}, "sounds/voices"), "."),
      el("div", { class: "inline" }, el("label", {}, "Sample rate ", rate), el("label", {}, "Ogg quality ", q, qv)),
      status.ffmpeg ? null : el("p", { class: "err" }, "ffmpeg wasn't found on PATH; it's needed to convert files."));
    return el("section", { class: "cast-sec" }, el("h2", {}, "Setup"), el("div", { class: "setup" }, eleven, ten, out));
  }

  function slider(sc, key, label, min, max, step) {
    const s = sc.settings || (sc.settings = Object.assign({}, DEFAULT_SETTINGS));
    const v = s[key] ?? DEFAULT_SETTINGS[key];
    const out = el("span", {}, String(v));
    return el("label", { class: "sl" }, el("span", {}, label), el("input", { type: "range", min, max, step, value: v,
      oninput: (e) => { s[key] = +e.target.value; out.textContent = e.target.value; touch(); } }), out);
  }

  function speakersSection() {
    const rows = [];
    for (const [name, count] of speakers()) {
      const sc = speakerCfg(name);
      const lines = catalog.dialogue.filter((d) => lineCast(d) === name);
      const voiced = lines.filter((d) => config.voices[d.id]).length;
      const voiceSel = el("select", { "aria-label": "Voice for " + name, onchange: (e) => {
        const v = voices.find((x) => x.voice_id === e.target.value);
        sc.voice_id = e.target.value || undefined;
        sc.voice_name = v ? v.name : undefined;
        touch(); render();
      } }, el("option", { value: "" }, voices.length ? "— choose a voice —" : (sc.voice_name || "— connect ElevenLabs —")),
      ...voices.map((v) => el("option", { value: v.voice_id, selected: v.voice_id === sc.voice_id || null },
        v.name + (v.labels && (v.labels.gender || v.labels.accent) ? ` (${[v.labels.gender, v.labels.age, v.labels.accent].filter(Boolean).join(", ")})` : ""))));
      if (sc.voice_id && !voices.find((v) => v.voice_id === sc.voice_id)) {
        voiceSel.append(el("option", { value: sc.voice_id, selected: true }, sc.voice_name || sc.voice_id));
      }
      const v = voices.find((x) => x.voice_id === sc.voice_id);
      const modelSel = el("select", { "aria-label": "Model for " + name, onchange: (e) => { sc.model_id = e.target.value; touch(); } },
        ...(models.length ? models : [{ model_id: sc.model_id || "eleven_multilingual_v2", name: sc.model_id || "eleven_multilingual_v2" }])
          .map((m) => el("option", { value: m.model_id, selected: m.model_id === (sc.model_id || "eleven_multilingual_v2") || null },
            m.name + (m.cost && m.cost !== 1 ? ` (×${m.cost} credits)` : ""))));
      const presetSel = el("select", { "aria-label": "Effect preset for " + name, onchange: (e) => { sc.preset = e.target.value; touch(); } },
        el("option", { value: "" }, "No effects"),
        ...Object.keys(cast.presets).map((p) => el("option", { value: p, selected: p === sc.preset || null }, p)));
      const unvoiced = lines.length - voiced;
      rows.push(el("div", { class: "spk" + (sc.voice_id ? " cast" : "") },
        el("div", { class: "spk-name" }, el("b", {}, name), el("div", { class: "muted" }, `${voiced} of ${lines.length} lines voiced`)),
        el("div", { class: "spk-voice" }, voiceSel,
          v && v.preview_url ? el("button", { class: "icon", "aria-label": "Hear " + v.name, onclick: () => playUrl(v.preview_url, v.name) }, "▶") : null),
        modelSel, presetSel,
        el("details", { class: "spk-set" }, el("summary", {}, "Voice settings"),
          slider(sc, "stability", "Stability", 0, 1, 0.05), slider(sc, "similarity_boost", "Similarity", 0, 1, 0.05),
          slider(sc, "style", "Style", 0, 1, 0.05), slider(sc, "speed", "Speed", 0.7, 1.2, 0.01),
          el("label", { class: "check" }, el("input", { type: "checkbox", checked: (sc.settings.use_speaker_boost ?? true) || null,
            onchange: (e) => { sc.settings.use_speaker_boost = e.target.checked; touch(); } }), "Speaker boost")),
        el("button", { class: "small", disabled: !sc.voice_id || !unvoiced || null,
          onclick: () => bulk("generate", lines) }, unvoiced ? `Generate ${unvoiced} unvoiced` : "All voiced")));
    }
    return el("section", { class: "cast-sec" }, el("h2", {}, "Speakers"),
      el("p", { class: "hint" }, "Choose an ElevenLabs voice, model and effect preset for each speaker. A single line can be voiced as another speaker from its Spoken text panel."),
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
        cast.presets[n] = { steps: [] }; currentPreset = n; touch(); render();
      } }, "+ New preset"));
    const sec = el("section", { class: "cast-sec" }, el("h2", {}, "Effect presets"),
      el("p", { class: "hint" }, "A preset is a list of Tenacity commands (the same lines as a Tenacity macro), applied to the whole take in order. Resampling to the output rate always happens last."));
    sec.append(el("div", { class: "presets" }, list, currentPreset ? presetEditor(currentPreset) : el("p", { class: "muted" }, "No presets yet.")));
    return sec;
  }

  function effectChoices() {
    if (!commands) return [];
    // effects worth offering: things that change the audio
    const skip = /^(Select|Set|Get|Import|Export|Open|Save|Close|New|Help|Message|Screenshot|Drag|Compare|Comment|Clear|Remove|Add|Copy|Cut|Paste|Undo|Redo|Zoom|Fit|Play|Stop|Record|Pause|Cursor|Track|Prev|Next|Last|First|Toggle|Collapse|Expand|Mute|Unmute|Pan|Gain|Label|Edit|Macro|Manage|Apply|Preferences|Exit|Full|Show|Hide|Reset|Sync|Skip|Mix|Align|Move|Sort|Split|Join|Detach|Silence|Trim|Duplicate|Rescan|Scrub|Seek|Spectral|Snap|Lock|Unlock|Punch|Sound|Timer|Plot|Contrast|Karaoke|Benchmark|Raw|Audio|Device|Input|Output|Rate|Keyboard|Manual|Quick|Check|About|Updates|Log|Nyquist_Plug|Nyquist_Prompt|Regular|Rhythm|Risset|Chirp|DTMF|Noise$|Tone|Pluck|Beat|Find|Sample_Data|Repeat|Paulstretch|Sliding)/;
    return commands.filter((c) => c.params && c.params.length && !skip.test(c.id)).sort((a, b) => a.name.localeCompare(b.name));
  }

  function paramFields(cmd, step, onChange) {
    const box = el("div", { class: "params" });
    for (const p of cmd.params) {
      const cur = step.params[p.key] !== undefined ? step.params[p.key] : p.default;
      let input;
      const set = (v) => { step.params[p.key] = v; onChange(); };
      if (p.type === "bool") {
        input = el("input", { type: "checkbox", checked: (cur === true || cur === "1" || cur === 1 || cur === "true") || null,
          onchange: (e) => set(e.target.checked ? 1 : 0) });
      } else if (p.type === "enum" && Array.isArray(p.enum)) {
        input = el("select", { onchange: (e) => set(e.target.value) },
          ...p.enum.map((o) => el("option", { value: o, selected: String(o) === String(cur) || null }, o)));
      } else {
        input = el("input", { type: p.type === "string" ? "text" : "number", value: cur ?? "", step: "any",
          onchange: (e) => set(e.target.value) });
      }
      box.append(el("label", {}, el("span", {}, p.key), input));
    }
    return box;
  }

  function presetEditor(name) {
    const preset = cast.presets[name];
    const steps = preset.steps || (preset.steps = []);
    const box = el("div", { class: "preset-ed" });
    const redraw = () => render();
    const stepRows = steps.map((line, i) => {
      const parsed = parseStep(line);
      const cmd = commands && commands.find((c) => c.id === parsed.id);
      const text = el("input", { type: "text", class: "mono", value: line, "aria-label": `Step ${i + 1}`,
        onchange: (e) => { steps[i] = e.target.value; touch(); redraw(); } });
      const row = el("div", { class: "step" },
        el("span", { class: "num" }, String(i + 1)), text,
        el("button", { class: "icon", "aria-label": "Move up", disabled: i === 0 || null, onclick: () => { [steps[i - 1], steps[i]] = [steps[i], steps[i - 1]]; touch(); redraw(); } }, "↑"),
        el("button", { class: "icon", "aria-label": "Move down", disabled: i === steps.length - 1 || null, onclick: () => { [steps[i + 1], steps[i]] = [steps[i], steps[i + 1]]; touch(); redraw(); } }, "↓"),
        el("button", { class: "icon", "aria-label": "Remove step", onclick: () => { steps.splice(i, 1); touch(); redraw(); } }, "✕"));
      if (cmd && cmd.params.length) {
        const det = el("details", { class: "step-params" }, el("summary", {}, cmd.name + " settings"),
          paramFields(cmd, parsed, () => { steps[i] = stepText(parsed.id, parsed.params); text.value = steps[i]; touch(); }));
        return el("div", {}, row, det);
      }
      return row;
    });
    const effects = effectChoices();
    const addSel = el("select", { "aria-label": "Add an effect", onchange: (e) => {
      const c = commands.find((x) => x.id === e.target.value);
      if (!c) return;
      const params = {};
      for (const p of c.params) if (p.default !== undefined) params[p.key] = typeof p.default === "boolean" ? (p.default ? 1 : 0) : p.default;
      steps.push(stepText(c.id, params));
      touch(); redraw();
    } }, el("option", { value: "" }, commands ? "+ Add a Tenacity effect…" : "+ Add effect (connect Tenacity for the list)"),
    ...effects.map((c) => el("option", { value: c.id }, c.name)));

    // test the preset
    const sources = [];
    for (const d of catalog.dialogue) if (takes[d.id] && takes[d.id].takes.length) sources.push(["take:" + d.id, "Take: " + d.id]);
    for (const s of catalog.sounds) sources.push(["sound:" + s.name, "Sound: " + (s.folder ? s.folder + "/" : "") + s.name]);
    if (!testSource && sources.length) testSource = sources[0][0];
    const srcSel = el("select", { "aria-label": "Audio to test the preset on", onchange: (e) => { testSource = e.target.value; } },
      ...sources.slice(0, 1500).map(([v, l]) => el("option", { value: v, selected: v === testSource || null }, l)));
    const test = el("button", { class: "primary small", disabled: !status.tenacity || null, onclick: async () => {
      test.disabled = true; test.textContent = "Processing…";
      try {
        const res = await api("/api/voice/preview", { method: "POST", json: { steps, rate: cast.output.rate, source: testSource } });
        playUrl(res.url, "preview");
      } catch (e) { toast(e.message); }
      test.disabled = false; test.textContent = "▶ Test preset";
    } }, "▶ Test preset");

    const macroSel = el("select", { "aria-label": "Import a Tenacity macro", onchange: (e) => {
      const m = macros[e.target.value];
      if (!m) return;
      preset.steps = m.slice(); touch(); redraw(); toast("Imported macro " + e.target.value);
    } }, el("option", { value: "" }, "Import a Tenacity macro…"), ...Object.keys(macros).map((m) => el("option", { value: m }, m)));

    box.append(
      el("div", { class: "preset-head" }, el("h3", {}, name),
        el("button", { class: "small", onclick: () => {
          const n = prompt("Rename preset", name);
          if (!n || n === name || cast.presets[n]) return;
          cast.presets[n] = preset; delete cast.presets[name];
          for (const sc of Object.values(cast.speakers)) if (sc.preset === name) sc.preset = n;
          currentPreset = n; touch(); redraw();
        } }, "Rename"),
        el("button", { class: "small", onclick: () => {
          let n = name + " copy", k = 2;
          while (cast.presets[n]) n = `${name} copy ${k++}`;
          cast.presets[n] = { steps: steps.slice() }; currentPreset = n; touch(); redraw();
        } }, "Duplicate"),
        el("button", { class: "small", onclick: () => {
          if (!confirm(`Delete the preset "${name}"?`)) return;
          delete cast.presets[name];
          for (const sc of Object.values(cast.speakers)) if (sc.preset === name) sc.preset = "";
          touch(); redraw();
        } }, "Delete")),
      el("div", { class: "steps" }, ...(stepRows.length ? stepRows : [el("p", { class: "muted" }, "No effects: the take is only resampled.")])),
      el("div", { class: "inline" }, addSel,
        el("button", { class: "small", onclick: () => { steps.push(""); touch(); redraw(); } }, "+ Blank step")),
      el("div", { class: "step final" }, el("span", { class: "num" }, "∎"),
        el("span", { class: "mono muted" }, `SetProject: Rate=${cast.output.rate}  → export mono → Ogg`)),
      el("div", { class: "inline test" }, el("span", {}, "Test on"), srcSel, test),
      el("div", { class: "inline" }, macroSel,
        el("button", { class: "small", onclick: async () => {
          try {
            const res = await api("/api/tenacity/macros", { method: "POST", json: { name, steps } });
            macros[res.name] = steps.slice();
            toast(`Saved as the Tenacity macro "${res.name}"`);
          } catch (e) { toast(e.message); }
        } }, "Save as Tenacity macro")),
      el("p", { class: "hint" }, "After changing a preset, use Re-process on lines (or “Re-process shown lines” in Voices & dialogue) to apply it without spending credits."));
    return box;
  }

  return { load, save, render, rowControls, spokenEditor, bulk, isDirty: () => dirty };
})();
