// Voices: SAM (Software Automatic Mouth), spoken live by the game.
// Voice casting sets each speaker's SAM voice and the pronunciation
// dictionary; each line in "Voices & dialogue" shows how SAM will say it.
// Nothing is recorded: the game's built-in SAM reads the real text as it
// happens. (Loaded before app.js; uses its helpers at run time.)
"use strict";

const Voices = (() => {
  const KEYS = [["speed", "Speed", "Higher is slower"], ["pitch", "Pitch", "Lower is higher"],
    ["throat", "Throat", "Shapes the vowels"], ["mouth", "Mouth", "Shapes the vowels"]];
  let cast = { speakers: {}, lines: {} };
  let sam = { installed: false, voices: {}, effects: {}, presets: {}, dictionary: "" };
  const openSettings = new Set(); // speakers whose SAM settings are open (kept across redraws)
  let dirty = false;
  const redraws = new Map(); // line id -> redraw its dialogue row

  // the casting saves itself shortly after a change; so does the dictionary
  let saveTimer = null, dictTimer = null;
  const touch = () => {
    dirty = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => save().catch((e) => toast("Couldn't save the voice casting: " + e.message)), 700);
  };
  const saveDict = () => {
    clearTimeout(dictTimer);
    dictTimer = null;
    return api("/api/sam/dictionary", { method: "PUT", json: { text: sam.dictionary } })
      .catch((e) => toast("Couldn't save the dictionary: " + e.message));
  };
  const touchDict = () => {
    clearTimeout(dictTimer);
    dictTimer = setTimeout(saveDict, 700);
  };

  // ---------------------------------------------------------- loading
  async function load() {
    [cast, sam] = await Promise.all([api("/api/cast"), api("/api/sam")]);
    cast.speakers = cast.speakers || {};
    cast.lines = cast.lines || {};
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
  const samOf = (name) => (cast.speakers[name] || {}).sam || {};
  function samCfg(name) {
    const sc = cast.speakers[name] || (cast.speakers[name] = {});
    if (!sc.sam) sc.sam = Object.assign({ voice: "SAM" }, sam.voices.SAM || {});
    return sc.sam;
  }
  // is this line spoken live by SAM in the game?
  const isLive = (d) => !!samOf(lineCast(d)).live;
  // a line's SAM settings: its own named voice, else its speaker's
  function samFor(d) {
    const ss = samOf(lineCast(d));
    const ln = cast.lines[d.id] || {};
    return ln.sam_voice && sam.voices[ln.sam_voice] ? Object.assign({}, ss, { voice: ln.sam_voice }, sam.voices[ln.sam_voice]) : ss;
  }
  // what SAM reads for a line in the editor: its own SAM text, else the
  // catalog text (the game reads the real one, names and all)
  const samText = (d) => (cast.lines[d.id] && cast.lines[d.id].sam_text) || d.spoken;
  const isCustom = (ss) => { const v = sam.voices[ss.voice]; return !v || KEYS.some(([k]) => ss[k] !== undefined && +ss[k] !== v[k]); };
  const voiceLabel = (ss) => (ss.voice || "SAM") + (isCustom(ss) ? " (custom)" : "");

  function setLine(id, key, value) {
    const ln = cast.lines[id] || (cast.lines[id] = {});
    if (value === undefined || value === null || value === "") delete ln[key]; else ln[key] = value;
    if (!Object.keys(ln).length) delete cast.lines[id];
    touch();
  }

  function redrawLine(id) {
    const f = redraws.get(id);
    if (f) f();
  }

  // ▶: SAM says it, as the game will (variety: three monsters of the kind)
  async function hear(btn, ss, text, opts = {}) {
    const label = btn.textContent;
    btn.disabled = true;
    btn.textContent = "…";
    try {
      if (dictTimer) await saveDict(); // (previews read the dictionary file)
      const res = await api("/api/sam/sample", { method: "POST", json: Object.assign({ sam: ss, text: text || "" }, opts) });
      playUrl(res.url, "SAM");
    } catch (e) { toast(e.message); }
    btn.disabled = false;
    btn.textContent = label;
  }

  async function showPhonemes(box, ss, text) {
    try {
      if (dictTimer) await saveDict();
      const res = await api("/api/sam/phonemes", { method: "POST", json: { sam: ss, text } });
      box.replaceChildren(el("div", { class: "muted" }, "SAM reads (copy a part into {…} to fix it):"),
        ...res.pieces.map((p) => el("code", { class: "phon" }, p)));
      box.hidden = false;
    } catch (e) { toast(e.message); }
  }

  // ---------------------------------------------------------- dialogue rows
  function rowControls(d, redraw) {
    redraws.set(d.id, redraw);
    const ln = cast.lines[d.id] || {};
    const live = isLive(d);
    const sc = samOf(lineCast(d));
    const box = el("div", { class: "gen sam-row" + (live ? " live" : "") });
    const sel = el("select", { "aria-label": "SAM voice for this line", onchange: (e) => { setLine(d.id, "sam_voice", e.target.value); redrawLine(d.id); } },
      el("option", { value: "" }, `${lineCast(d)}'s voice: ${voiceLabel(sc)}`),
      ...Object.keys(sam.voices).map((v) => el("option", { value: v, selected: v === ln.sam_voice || null }, v)));
    const hearBtn = el("button", { class: "icon", "aria-label": "Hear SAM say this line", title: "Hear SAM say this line",
      disabled: !sam.installed || null, onclick: () => hear(hearBtn, samFor(d), samText(d)) }, "▶");
    box.append(el("div", { class: "genpick" }, el("label", {}, el("span", {}, "SAM"), el("div", { class: "with-play" }, sel, hearBtn))),
      el("div", { class: "jobnote" }, live ? "Spoken live by SAM in the game."
        : `Not spoken: tick “Speak live with SAM” for ${lineCast(d)} in Voice casting.`));
    return box;
  }

  // the line's SAM text: what SAM reads instead of the game's own text
  function spokenEditor(d) {
    const ln = cast.lines[d.id] || {};
    const edited = !!ln.sam_text;
    const det = el("details", { class: "spoken" });
    const summary = el("summary", {}, "SAM text" + (edited ? " (own text)" : ""),
      d.varies && d.varies.length && !edited ? el("span", { class: "varies" }, "changes in play: " + d.varies.join(", ")) : null,
      ln.cast ? el("span", { class: "castas" }, "voiced as " + ln.cast) : null);
    const ta = el("textarea", { rows: Math.min(10, Math.max(2, Math.ceil(samText(d).length / 80))),
      "aria-label": "What SAM reads for this line", placeholder: d.spoken,
      oninput: (e) => { setLine(d.id, "sam_text", e.target.value); } });
    ta.value = ln.sam_text || "";
    const castSel = el("select", { "aria-label": "Voice this line as", onchange: (e) => {
      setLine(d.id, "cast", e.target.value === d.speaker ? "" : e.target.value);
      redrawLine(d.id);
    } }, ...speakers().map(([s]) => el("option", { value: s, selected: s === lineCast(d) || null }, s)));
    const phon = el("div", { class: "phonemes", hidden: true });
    const hearBtn = el("button", { class: "small", disabled: !sam.installed || null,
      onclick: () => hear(hearBtn, samFor(d), ta.value || d.spoken) }, "▶ Hear");
    det.append(summary,
      el("p", { class: "muted" }, edited ? "SAM reads this instead of the game's text."
        : "Empty: SAM reads the game's own text, with the real names filled in. Write here to have it say something else; {PHONEMES} in braces are read as written."),
      ta, el("div", { class: "spoken-tools" },
        el("label", {}, "Voice as ", castSel), hearBtn,
        el("button", { class: "small", disabled: !sam.installed || null, onclick: () => showPhonemes(phon, samFor(d), ta.value || d.spoken) }, "Show phonemes"),
        el("button", { class: "small", onclick: () => { setLine(d.id, "sam_text", ""); ta.value = ""; } }, "Use the game's text")),
      phon);
    return det;
  }

  // ---------------------------------------------------------- casting tab
  function render() {
    const root = $("#castingBody");
    if (!root) return;
    root.replaceChildren(setupSection(), speakersSection(), dictionarySection());
  }

  function card(title, ok, ...kids) {
    return el("div", { class: "setup-card" + (ok ? " ok" : "") },
      el("h3", {}, el("span", { class: "dot", "aria-hidden": "true" }), title), ...kids);
  }

  function setupSection() {
    return el("section", { class: "cast-sec" }, el("h2", {}, "SAM"), el("div", { class: "setup" },
      card("Software Automatic Mouth", sam.installed,
        el("p", {}, "SAM, the 1982 Commodore 64 speech synth, is built into the game. A speaker ticked ",
          el("b", {}, "Speak live with SAM"), " has every line read by SAM as it happens, with the real text: your name, your god, the shopkeeper's name. Nothing is recorded."),
        el("p", { class: "muted" }, "Numbers and symbols are read as words; exclamations come out quicker and higher. Changes reach a running game within a couple of seconds. A line with a recording of its own (Upload) plays that unless its speaker is spoken by SAM."),
        sam.installed ? null : el("p", { class: "err" }, "Previews need build/sam/samtool.exe: run tools/deploy.sh to build it."))));
  }

  function slider(label, value, min, max, step, unit, onInput, title) {
    const show = (v) => `${+(+v).toFixed(2)}${unit || ""}`;
    const out = el("span", {}, show(value));
    return el("label", { class: "sl", title: title || null }, el("span", {}, label), el("input", { type: "range", min, max, step, value,
      oninput: (e) => { out.textContent = show(e.target.value); onInput(+e.target.value); } }), out);
  }

  function check(label, on, onChange, title) {
    return el("label", { class: "check", title: title || null }, el("input", { type: "checkbox", checked: on || null,
      onchange: (e) => onChange(e.target.checked) }), " " + label);
  }

  function speakersSection() {
    const rows = [];
    for (const [name] of speakers()) {
      const ss = samOf(name);
      const lines = catalog.dialogue.filter((d) => lineCast(d) === name);
      const set = (k, v) => { samCfg(name)[k] = v; touch(); };
      const live = check("Speak live with SAM", ss.live, (on) => { set("live", on); render(); redraws.forEach((f) => f()); },
        "The game's SAM reads this speaker's lines as they happen");
      const voiceSel = el("select", { "aria-label": "SAM voice for " + name, onchange: (e) => {
        Object.assign(samCfg(name), { voice: e.target.value }, sam.voices[e.target.value] || {});
        touch(); render();
      } }, ...Object.keys(sam.voices).map((v) => el("option", { value: v, selected: v === (ss.voice || "SAM") || null }, v + (v === ss.voice && isCustom(ss) ? " (custom)" : ""))));
      const hearBtn = el("button", { class: "icon", "aria-label": "Hear " + name, title: "Hear this voice",
        disabled: !sam.installed || null, onclick: () => hear(hearBtn, samCfg(name)) }, "▶");
      const varietyBtn = el("button", { class: "small", title: "Three different monsters of this kind, one after another (Variation)",
        disabled: !sam.installed || null, onclick: () => hear(varietyBtn, samCfg(name), "", { variety: true }) }, "▶ ×3");
      const femaleBtn = el("button", { class: "small", title: "As a female monster says it (Female voice)",
        disabled: !sam.installed || null, onclick: () => hear(femaleBtn, samCfg(name), "", { female: true }) }, "▶ ♀");
      const base = sam.voices[ss.voice || "SAM"] || sam.voices.SAM || {};
      const settings = el("details", { class: "spk-set", open: openSettings.has(name) || null,
        ontoggle: (e) => { if (e.target.open) openSettings.add(name); else openSettings.delete(name); } },
      el("summary", {}, "SAM settings" + ((ss.effects || []).some((f) => !f.off) ? " · effects" : "")),
      el("div", { class: "spk-set-body" },
        ...KEYS.map(([k, l, tip]) => slider(l, ss[k] ?? base[k] ?? 128, 1, 255, 1, "", (v) => set(k, v), tip)),
        slider("Volume", ss.volume ?? 100, 0, 200, 5, "%", (v) => set("volume", v)),
        slider("Variation", ss.variation ?? 25, 0, 100, 5, "%", (v) => set("variation", v),
          "How much each monster of this kind differs from the others (pitch, speed, throat, mouth)"),
        slider("Female voice", ss.female ?? 12, 0, 40, 1, "", (v) => set("female", v),
          "How much higher a female monster speaks (SAM pitch steps)"),
        el("label", { class: "sl sel", title: "SAM's harsh 8-bit sound as it was, softened for long listening, "
            + "or Hi-fi: SAM's speech voiced anew in full quality (smooth, breathy, a natural pitch)" },
          el("span", {}, "Sound"), el("select", { onchange: (e) => {
            set("smooth", e.target.value === "1");
            set("hifi", e.target.value === "2");
          } },
            el("option", { value: "0", selected: (!ss.smooth && !ss.hifi) || null }, "Authentic (8-bit)"),
            el("option", { value: "1", selected: (ss.smooth && !ss.hifi) || null }, "Smoothed"),
            el("option", { value: "2", selected: ss.hifi || null }, "Hi-fi"))),
        check("Size changes the voice", ss.size !== false, (on) => set("size", on), "Big monsters deeper, small ones higher"),
        check("Exclamations quicker and higher", ss.tone !== false, (on) => set("tone", on)),
        check("Sing mode", ss.sing, (on) => set("sing", on), "SAM's sing mode: the pitch follows the phonemes"),
        effectsEditor(name)));
      rows.push(el("div", { class: "spk sam" + (ss.live ? " cast" : "") },
        el("div", { class: "spk-name" }, el("b", {}, name), el("div", { class: "muted" }, `${lines.length} line(s)`)),
        live, el("div", { class: "spk-voice" }, voiceSel, hearBtn, varietyBtn, femaleBtn), settings));
    }
    return el("section", { class: "cast-sec" }, el("h2", {}, "Speakers"),
      el("p", { class: "hint" }, "Tick the speakers SAM should voice in the game and pick each one's SAM voice, or shape your own in SAM settings. ▶ plays a sample, ▶ ×3 three monsters of the kind (Variation), ▶ ♀ a female one."),
      el("div", { class: "spk-list" }, ...rows));
  }

  // ------------------------------------------- effects
  // a speaker's effects, applied in order after SAM speaks (in the game too)
  function newEffect(type) {
    const fx = { type };
    for (const p of sam.effects[type].params) fx[p.key] = p.default;
    return fx;
  }

  function effectsEditor(name) {
    const ss = samOf(name);
    const list = ss.effects || [];
    const change = () => { touch(); render(); };
    const mine = () => samCfg(name).effects || (samCfg(name).effects = []);
    const types = Object.entries(sam.effects);
    const rows = list.map((fx, i) => {
      const def = sam.effects[fx.type];
      if (!def) return null;
      return el("div", { class: "fx" + (fx.off ? " off" : "") },
        el("div", { class: "fx-head" },
          el("input", { type: "checkbox", title: "On / off", "aria-label": def.name + " on", checked: !fx.off || null,
            onchange: (e) => { if (e.target.checked) delete mine()[i].off; else mine()[i].off = true; change(); } }),
          el("b", { title: def.tip }, def.name),
          el("button", { class: "icon", "aria-label": "Move up", disabled: i === 0 || null,
            onclick: () => { const l = mine(); [l[i - 1], l[i]] = [l[i], l[i - 1]]; change(); } }, "↑"),
          el("button", { class: "icon", "aria-label": "Move down", disabled: i === list.length - 1 || null,
            onclick: () => { const l = mine(); [l[i + 1], l[i]] = [l[i], l[i + 1]]; change(); } }, "↓"),
          el("button", { class: "icon", "aria-label": "Remove " + def.name, onclick: () => { mine().splice(i, 1); change(); } }, "✕")),
        el("div", { class: "fx-params" }, ...def.params.map((p) =>
          slider(p.label, fx[p.key] ?? p.default, p.min, p.max, p.step, p.unit, (v) => { mine()[i][p.key] = v; touch(); }))));
    });
    const add = el("select", { "aria-label": "Add an effect", onchange: (e) => {
      if (sam.effects[e.target.value]) { mine().push(newEffect(e.target.value)); change(); }
    } }, el("option", { value: "" }, "+ Add an effect…"), ...types.map(([id, d]) => el("option", { value: id, title: d.tip }, d.name)));
    const preset = el("select", { "aria-label": "Start from a preset", onchange: (e) => {
      const p = sam.presets[e.target.value];
      if (!p) return;
      samCfg(name).effects = JSON.parse(JSON.stringify(p));
      change();
    } }, el("option", { value: "" }, "Start from…"), ...Object.keys(sam.presets).map((n) => el("option", { value: n }, n)));
    const hearBtn = el("button", { class: "small", disabled: !sam.installed || null,
      onclick: () => hear(hearBtn, samCfg(name)) }, "▶ Hear with effects");
    return el("div", { class: "fx-list" },
      el("div", { class: "fx-title" }, el("b", {}, "Effects"), el("span", { class: "muted" }, "applied in order, live in the game")),
      ...(rows.filter(Boolean).length ? rows.filter(Boolean) : [el("p", { class: "muted" }, "None: SAM as it is.")]),
      el("div", { class: "inline" }, add, preset, hearBtn,
        list.length ? el("button", { class: "small", onclick: () => { samCfg(name).effects = []; change(); } }, "Clear") : null));
  }

  // ------------------------------------------- pronunciation dictionary
  // sam_dictionary.txt: "word = replacement" lines; comments are kept as they are
  function parseDict(text) {
    const entries = [];
    text.split("\n").forEach((line, i) => {
      const m = /^\s*([^#=]+?)\s*=\s*([^#]*?)\s*$/.exec(line);
      if (m) entries.push({ line: i, word: m[1], say: m[2] });
    });
    return entries;
  }
  function setEntry(lineNo, word, say) {
    const lines = sam.dictionary.split("\n");
    const text = word ? `${word} = ${say}` : null;
    if (lineNo === null) {
      if (lines.length && lines[lines.length - 1] === "") lines.pop();
      lines.push(text, "");
    } else if (text === null) {
      lines.splice(lineNo, 1);
    } else {
      lines[lineNo] = text;
    }
    sam.dictionary = lines.join("\n");
    touchDict();
  }

  function dictionarySection() {
    const entries = parseDict(sam.dictionary);
    const ss = sam.voices.SAM || {};
    const rows = entries.map((e) => {
      const word = el("input", { type: "text", value: e.word, "aria-label": "Word", onchange: (ev) => { setEntry(e.line, ev.target.value.trim(), say.value.trim()); render(); } });
      const say = el("input", { type: "text", value: e.say, class: "mono", "aria-label": "SAM says", onchange: (ev) => { setEntry(e.line, word.value.trim(), ev.target.value.trim()); } });
      const b = el("button", { class: "icon", "aria-label": "Hear " + e.word, disabled: !sam.installed || null, onclick: () => hear(b, ss, word.value) }, "▶");
      return el("div", { class: "dict-row" }, word, el("span", { class: "muted" }, "→"), say, b,
        el("button", { class: "icon", "aria-label": "Remove " + e.word, onclick: () => { setEntry(e.line, "", ""); render(); } }, "✕"));
    });
    const newWord = el("input", { type: "text", placeholder: "Word (e.g. Asidonhopo)", "aria-label": "New word" });
    const newSay = el("input", { type: "text", class: "mono", placeholder: "ah see don hoe poe   or   {AESIY4DAHN/HOWPOW}", "aria-label": "SAM says" });
    const before = el("button", { class: "small", disabled: !sam.installed || null, title: "How SAM says the word now",
      onclick: () => newWord.value && hear(before, ss, newWord.value) }, "▶ As is");
    const tryIt = el("button", { class: "small", disabled: !sam.installed || null, title: "How SAM says the replacement",
      onclick: () => newSay.value && hear(tryIt, ss, newSay.value) }, "▶ Replacement");
    const phon = el("div", { class: "phonemes", hidden: true });
    const add = el("button", { class: "primary small", onclick: () => {
      const w = newWord.value.trim(), s = newSay.value.trim();
      if (!w || !s) return toast("Fill in the word and what SAM should say");
      setEntry(null, w, s); render();
    } }, "Add");
    return el("section", { class: "cast-sec" }, el("h2", {}, "Pronunciation"),
      el("p", { class: "hint" }, "Words SAM gets wrong, and what it says instead, everywhere: a respelling (ah see don hoe poe) or SAM phonemes in braces ({KRIY4SAHS}; stress digits 1-8 set the emphasis). Whole words, any case; “Croesus's” uses “Croesus”."),
      el("div", { class: "dict" }, ...(rows.length ? rows : [el("p", { class: "muted" }, "No words yet.")])),
      el("div", { class: "dict-row new" }, newWord, el("span", { class: "muted" }, "→"), newSay, before, tryIt,
        el("button", { class: "small", disabled: !sam.installed || null, onclick: () => newWord.value && showPhonemes(phon, ss, newWord.value) }, "Phonemes"), add),
      phon);
  }

  return { load, save, render, rowControls, spokenEditor, isLive, isDirty: () => dirty };
})();
