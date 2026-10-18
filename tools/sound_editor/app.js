// NetHack Voxel sound & voice editor.
"use strict";

const GROUPS = {
  nethack: "NetHack sounds", events: "Events", traps: "Traps", game: "Game",
};
const MASTERS = [["effects", "Effects"], ["music", "Music"], ["voices", "Voices"]];
const PAGE = 60;

let catalog = { hooks: [], dialogue: [], sounds: [], folders: [] };
let config = { version: 1, hooks: {}, voices: {}, master: {} };
let dirty = false;
let voicePage = 0;
let audio = null;

const $ = (sel) => document.querySelector(sel);
const el = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null && v !== false) e.setAttribute(k, v);
  }
  for (const kid of kids) if (kid !== null && kid !== undefined) e.append(kid);
  return e;
};

// every API call carries this header: the server refuses calls without it,
// so other web pages can't use the editor (or your ElevenLabs credits)
async function api(path, opts = {}) {
  opts.headers = Object.assign({ "X-NHV": "1" }, opts.headers || {});
  if (opts.json !== undefined) {
    opts.body = JSON.stringify(opts.json);
    opts.headers["Content-Type"] = "application/json";
    delete opts.json;
  }
  const r = await fetch(path, opts);
  let res = null;
  try { res = await r.json(); } catch (e) { res = null; }
  if (!r.ok) throw new Error((res && res.error) || r.statusText);
  return res;
}

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), Math.max(2600, msg.length * 60));
}

function markDirty() {
  dirty = true;
  $("#dirty").hidden = false;
  $("#saveBtn").disabled = false;
}

function play(name) {
  const s = catalog.sounds.find((x) => x.name === name);
  if (s && s.midi) {
    toast("MIDI music plays in the game (with its SoundFont); there's no preview here.");
    return;
  }
  playUrl(`/sounds/${name}.ogg`, name);
}

function playUrl(url, label) {
  if (audio) audio.pause();
  audio = new Audio(url + (url.includes("?") ? "&" : "?") + "t=" + Date.now());
  audio.play().catch(() => toast("Could not play " + (label || url)));
}

// ------------------------------------------------------------ loading/saving
async function load() {
  const [cat, cfg] = await Promise.all([api("/api/catalog"), api("/api/config"), VoiceGen.load()]);
  catalog = cat;
  config = cfg;
  config.hooks = config.hooks || {};
  config.voices = config.voices || {};
  config.master = Object.assign({ effects: 100, music: 60, voices: 100 }, config.master || {});
  renderMasters();
  renderGroups();
  renderHooks();
  renderMusic();
  renderVoiceFilters();
  renderLegend();
  renderVoices();
  renderLibrary();
  VoiceGen.render();
}

async function save() {
  try {
    await api("/api/config", { method: "PUT", json: config });
    await VoiceGen.save();
  } catch (e) {
    return toast("Saving failed: " + e.message);
  }
  dirty = false;
  $("#dirty").hidden = true;
  $("#saveBtn").disabled = true;
  toast("Saved — the game picks it up in a couple of seconds");
}

// upload one audio file into a library folder; returns the sound's name
// (made unique across all folders unless replace is set)
async function upload(file, name, folder = "", replace = false) {
  const q = new URLSearchParams({ name, filename: file.name, folder, replace: replace ? "1" : "0" });
  const res = await api("/api/upload?" + q, { method: "POST", body: file });
  catalog.sounds = catalog.sounds.filter((s) => s.name !== res.name);
  catalog.sounds.push({ name: res.name, folder: res.folder, size: file.size, midi: !!res.midi });
  catalog.sounds.sort((a, b) => a.name.localeCompare(b.name));
  addFolderPath(res.folder);
  return res.name;
}

function addFolderPath(folder) {
  const parts = (folder || "").split("/").filter(Boolean);
  for (let i = 1; i <= parts.length; i++) {
    const f = parts.slice(0, i).join("/");
    if (!catalog.folders.includes(f)) catalog.folders.push(f);
  }
  catalog.folders.sort();
}

function addSound(name, folder) {
  if (catalog.sounds.find((s) => s.name === name)) return;
  catalog.sounds.push({ name, folder: folder || "", size: 0 });
  catalog.sounds.sort((a, b) => a.name.localeCompare(b.name));
  addFolderPath(folder);
}

const baseName = (fname) => fname.replace(/\.[^.]+$/, "").toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_|_$/g, "");

// ------------------------------------------------------------ masters
function renderMasters() {
  const box = $("#masters");
  box.textContent = "";
  for (const [key, label] of MASTERS) {
    const out = el("span", {}, String(config.master[key]));
    const input = el("input", { type: "range", min: 0, max: 100, value: config.master[key],
      "aria-label": label + " volume",
      oninput: (e) => { config.master[key] = +e.target.value; out.textContent = e.target.value; markDirty(); } });
    box.append(el("label", {}, el("span", {}, label + " ", out), input));
  }
}

// ------------------------------------------------------------ sound picker
let pickerCallback = null;
// (music: MIDI tracks are offered too; other hooks only get .ogg sounds)
let pickerMusic = false;
function openPicker(title, cb, music = false) {
  pickerCallback = cb;
  pickerMusic = music;
  $("#pickerTitle").textContent = title;
  $("#pickerSearch").value = "";
  renderPicker();
  $("#picker").hidden = false;
  $("#pickerSearch").focus();
}
function closePicker() { $("#picker").hidden = true; pickerCallback = null; }
function renderPicker() {
  const q = $("#pickerSearch").value.trim().toLowerCase();
  const list = $("#pickerList");
  list.textContent = "";
  for (const s of catalog.sounds) {
    if (q && !(s.name.includes(q) || (s.folder || "").includes(q))) continue;
    if (s.midi && !pickerMusic) continue;
    list.append(el("div", { class: "pick" },
      el("button", { class: "icon", "aria-label": "Play " + s.name, onclick: () => play(s.name) }, "▶"),
      s.folder ? el("span", { class: "folder-tag" }, s.folder) : null,
      s.midi ? el("span", { class: "folder-tag" }, "MIDI") : null,
      el("span", { class: "name", role: "button", tabindex: 0,
        onclick: () => { const cb = pickerCallback; closePicker(); cb && cb(s.name); },
        onkeydown: (e) => { if (e.key === "Enter") e.target.click(); } }, s.name)));
  }
}

// ------------------------------------------------------------ hook rows
function hookRow(h, isMusic) {
  const entry = config.hooks[h.id];
  const row = el("div", { class: "row" + (entry && entry.sounds && entry.sounds.length ? " assigned" : "") });
  const sounds = el("div", { class: "sounds" });
  const redraw = () => row.replaceWith(hookRow(h, isMusic));
  for (const name of (entry && entry.sounds) || []) {
    sounds.append(el("span", { class: "snd" }, name,
      el("button", { "aria-label": "Play " + name, onclick: () => play(name) }, "▶"),
      el("button", { "aria-label": "Remove " + name, onclick: () => {
        entry.sounds = entry.sounds.filter((n) => n !== name);
        if (!entry.sounds.length) delete config.hooks[h.id];
        markDirty(); redraw();
      } }, "✕")));
  }
  sounds.append(el("button", { class: "add", onclick: () => openPicker(`Sound for “${h.id}”`, (name) => {
    const e = config.hooks[h.id] || (config.hooks[h.id] = { sounds: [], volume: 100, pitch_var: isMusic ? 0 : 0.05 });
    if (isMusic) { e.sounds = [name]; e.loop = true; } else if (!e.sounds.includes(name)) e.sounds.push(name);
    markDirty(); redraw();
  }, isMusic) }, isMusic ? (entry ? "Change…" : "+ Choose music") : "+ Add sound"));

  const controls = el("div", { class: "controls" });
  if (entry) {
    const vol = el("span", {}, entry.volume ?? 100);
    controls.append("Volume", el("input", { type: "range", min: 0, max: 150, value: entry.volume ?? 100,
      "aria-label": "Volume", oninput: (e) => { entry.volume = +e.target.value; vol.textContent = e.target.value; markDirty(); } }), vol);
    if (!isMusic) {
      const pv = el("span", {}, Math.round((entry.pitch_var ?? 0) * 100) + "%");
      controls.append("Pitch ±", el("input", { type: "range", min: 0, max: 30, value: Math.round((entry.pitch_var ?? 0) * 100),
        "aria-label": "Pitch variation", oninput: (e) => { entry.pitch_var = +e.target.value / 100; pv.textContent = e.target.value + "%"; markDirty(); } }), pv);
      // the hero's own voice: pitched up in the game for a female hero
      controls.append(el("label", { class: "check", title: "The hero's own voice: higher for a female hero" },
        el("input", { type: "checkbox", checked: entry.player_voice || null,
          onchange: (e) => { if (e.target.checked) entry.player_voice = true; else delete entry.player_voice; markDirty(); } }),
        " Player voice"));
    }
  }
  row.append(
    el("div", {}, el("div", { class: "group" }, GROUPS[h.group] || h.group),
      el("div", { class: "id" }, h.id), el("div", { class: "desc" }, h.desc || "")),
    sounds, controls);
  return row;
}

let hookGroup = "";
function renderGroups() {
  const box = $("#hookGroups");
  box.textContent = "";
  for (const [g, label] of [["", "All"], ...Object.entries(GROUPS)]) {
    box.append(el("button", { class: "chip", "aria-pressed": String(hookGroup === g),
      onclick: () => { hookGroup = g; renderGroups(); renderHooks(); } }, label));
  }
}

function renderHooks() {
  const q = $("#hookSearch").value.trim().toLowerCase();
  const onlyEmpty = $("#hookUnassigned").checked;
  const list = $("#hookList");
  list.textContent = "";
  let n = 0;
  for (const h of catalog.hooks) {
    if (h.group === "music") continue;
    if (hookGroup && h.group !== hookGroup) continue;
    if (q && !(h.id.includes(q) || (h.desc || "").toLowerCase().includes(q))) continue;
    const assigned = config.hooks[h.id] && (config.hooks[h.id].sounds || []).length;
    if (onlyEmpty && assigned) continue;
    list.append(hookRow(h, false));
    n++;
  }
  const total = catalog.hooks.filter((h) => h.group !== "music").length;
  const done = catalog.hooks.filter((h) => h.group !== "music" && config.hooks[h.id]).length;
  $("#hookCount").textContent = `${n} shown · ${done} of ${total} hooks have sounds`;
}

function renderMusic() {
  const list = $("#musicList");
  list.textContent = "";
  for (const h of catalog.hooks.filter((h) => h.group === "music")) list.append(hookRow(h, true));
}

// ------------------------------------------------------------ voices
function renderVoiceFilters() {
  const cats = [...new Set(catalog.dialogue.map((d) => d.category))].sort();
  const speakers = [...new Set(catalog.dialogue.map((d) => d.speaker))].sort();
  $("#voiceCategory").replaceChildren(el("option", { value: "" }, "All categories"),
    ...cats.map((c) => el("option", { value: c }, c)));
  $("#voiceSpeaker").replaceChildren(el("option", { value: "" }, "All speakers"),
    ...speakers.map((s) => el("option", { value: s }, s)));
}

function filteredDialogue() {
  const q = $("#voiceSearch").value.trim().toLowerCase();
  const cat = $("#voiceCategory").value, who = $("#voiceSpeaker").value, st = $("#voiceState").value;
  return catalog.dialogue.filter((d) => {
    if (cat && d.category !== cat) return false;
    if (who && d.speaker !== who) return false;
    const voiced = !!config.voices[d.id];
    if (st === "voiced" && !voiced) return false;
    if (st === "unvoiced" && voiced) return false;
    if (st === "review" && !VoiceGen.awaitingReview(d.id)) return false;
    if (q && !(d.text.toLowerCase().includes(q) || d.id.toLowerCase().includes(q) || d.speaker.toLowerCase().includes(q))) return false;
    return true;
  });
}

// the line's text with each placeholder marked; hover (or focus) one to
// see what it means and what it becomes in this line
function highlight(d) {
  const frag = document.createDocumentFragment();
  const text = d.text;
  let last = 0;
  for (const t of d.tokens || []) {
    const at = text.indexOf(t.text, last);
    if (at < 0) continue;
    let tip = `${t.mark || t.text} — ${t.meaning}`;
    if (t.varies) tip += t.value ? `\nChanges from game to game, so it's spoken as “${t.value}”.` : "\nChanges from game to game, so it's left out of the spoken text.";
    else if (t.value) tip += `\nHere: “${t.value}”`;
    frag.append(text.slice(last, at),
      el("mark", { class: t.mark ? "note" : t.varies ? "varies" : null, title: tip, tabindex: 0, "aria-label": tip }, t.text));
    last = at + t.text.length;
  }
  frag.append(text.slice(last));
  return frag;
}

// the placeholder legend above the dialogue list
function renderLegend() {
  const lg = catalog.legend;
  if (!lg) return;
  const table = (rows) => el("table", { class: "legend-table" },
    el("tbody", {}, ...rows.map(([code, what]) => el("tr", {}, el("td", {}, el("code", {}, code)), el("td", {}, what)))));
  $("#legendBody").replaceChildren(
    el("div", { class: "legend-col" },
      el("h3", {}, "Quest text"),
      el("p", { class: "muted" }, "Used in the quest category. Codes for the leader, nemesis, artifact and places are filled in with each role's real names; marked ones (your name, god, gender) change from game to game."),
      table(Object.entries(lg.quest).map(([c, w]) => ["%" + c, lg.quest_varies.includes(c)
        ? el("span", {}, w, " ", el("span", { class: "varies-tag" }, "changes per game")) : w])),
      el("h4", {}, "A letter right after the code changes it"),
      el("p", { class: "muted" }, "For example %na is the nemesis with a/an in front, and %lh is the leader as he/she/it."),
      table(Object.entries(lg.quest_mods).map(([m, w]) => [("hHiIjJ".includes(m) ? "%l" : "%n") + m, w +("hHiIjJ".includes(m) ? ` (only after %${lg.pronoun_codes.split("").join(", %")})` : "")])),
      table([["%%", "a plain % sign"]])),
    el("div", { class: "legend-col" },
      el("h3", {}, "Everything else"),
      el("p", { class: "muted" }, "Ordinary game messages use C-style codes, filled in with whatever the situation needs. They change every time, so they're left out of the spoken text — reword those lines in Spoken text if they need it."),
      table(Object.entries(lg.printf).filter(([c]) => !["i", "u", "lu", "g", "X"].includes(c)).map(([c, w]) => ["%" + c, w])),
      el("p", { class: "muted" }, "Numbers or symbols between % and the letter (like %-12s or %ld) only set width or size; the meaning is the same."),
      el("p", { class: "muted" }, "Rumors, epitaphs, engravings, book passages and the Oracle are shown word for word: a % in them is just a % sign.")),
    el("div", { class: "legend-col legend-wide" },
      el("h3", {}, "Other markings in the text"),
      el("p", { class: "muted" }, "Not placeholders, but they change what's shown or spoken. They're underlined in the lines; hover one for details."),
      table((lg.marks || []).map(([label, what]) => [label, what.charAt(0).toUpperCase() + what.slice(1)]))));
}

function voiceRow(d) {
  const v = config.voices[d.id];
  const row = el("div", { class: "vrow" + (v ? " voiced" : "") });
  const voiceName = "voice_" + d.id.toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  const attach = async (file) => {
    try {
      toast("Converting " + file.name + "…");
      const name = await upload(file, voiceName.slice(0, 80), "voices", true);
      config.voices[d.id] = { sound: name, volume: 100 };
      markDirty();
      row.replaceWith(voiceRow(d));
      toast("Voice attached");
    } catch (e) { toast(e.message); }
  };
  const fileInput = el("input", { type: "file", accept: "audio/*", hidden: true,
    onchange: (e) => e.target.files[0] && attach(e.target.files[0]) });
  const voice = el("div", { class: "voice" });
  if (v) {
    voice.append(el("span", { class: "snd" }, v.sound,
      el("button", { "aria-label": "Play", onclick: () => play(v.sound) }, "▶"),
      el("button", { "aria-label": "Remove voice", onclick: () => { delete config.voices[d.id]; markDirty(); row.replaceWith(voiceRow(d)); } }, "✕")));
  }
  voice.append(VoiceGen.rowControls(d, () => row.replaceWith(voiceRow(d))));
  voice.append(el("label", { class: "button" }, v ? "Replace recording…" : "Upload recording…", fileInput),
    el("button", { class: "add", onclick: () => openPicker("Existing sound for this line", (name) => {
      config.voices[d.id] = { sound: name, volume: 100 }; markDirty(); row.replaceWith(voiceRow(d)); }) }, "Use a library sound"));
  row.addEventListener("dragover", (e) => { e.preventDefault(); row.classList.add("drop"); });
  row.addEventListener("dragleave", () => row.classList.remove("drop"));
  row.addEventListener("drop", (e) => {
    e.preventDefault(); e.stopPropagation(); row.classList.remove("drop");
    if (e.dataTransfer.files[0]) attach(e.dataTransfer.files[0]);
  });
  row.append(
    el("div", { class: "meta" }, el("div", { class: "who" }, d.speaker),
      el("div", {}, d.category + " · " + d.context), el("div", { class: "vid" }, d.id),
      el("div", {}, d.source)),
    el("div", { class: "text" }, highlight(d), VoiceGen.spokenEditor(d)), voice);
  return row;
}

function renderVoices() {
  const items = filteredDialogue();
  const pages = Math.max(1, Math.ceil(items.length / PAGE));
  voicePage = Math.min(voicePage, pages - 1);
  const list = $("#voiceList");
  list.textContent = "";
  for (const d of items.slice(voicePage * PAGE, voicePage * PAGE + PAGE)) list.append(voiceRow(d));
  const voiced = catalog.dialogue.filter((d) => config.voices[d.id]).length;
  $("#voiceCount").textContent = `${items.length} lines shown · ${voiced} of ${catalog.dialogue.length} voiced`;
  const pager = $("#voicePager");
  pager.textContent = "";
  if (pages > 1) {
    pager.append(
      el("button", { disabled: voicePage === 0 || null, onclick: () => { voicePage--; renderVoices(); scrollTo(0, 0); } }, "← Previous"),
      `Page ${voicePage + 1} of ${pages}`,
      el("button", { disabled: voicePage >= pages - 1 || null, onclick: () => { voicePage++; renderVoices(); scrollTo(0, 0); } }, "Next →"));
  }
}

function exportScript() {
  const rows = [["id", "category", "speaker", "context", "text", "voice file"]];
  for (const d of filteredDialogue()) {
    rows.push([d.id, d.category, d.speaker, d.context, d.text, (config.voices[d.id] || {}).sound || ""]);
  }
  const csv = rows.map((r) => r.map((c) => '"' + String(c).replace(/"/g, '""') + '"').join(",")).join("\r\n");
  const a = el("a", { href: URL.createObjectURL(new Blob(["﻿" + csv], { type: "text/csv" })),
    download: "nethack-voxel-voice-script.csv" });
  document.body.append(a);
  a.click();
  a.remove();
}

// ------------------------------------------------------------ library
// Sounds live in folders under sounds/ (any depth). Sound names are global
// in the game, so a name is unique across all folders; imports that clash
// get a number added.
const AUDIO_EXT = /\.(wav|mp3|ogg|oga|flac|aif|aiff|m4a|opus|wma)$/i;
let libFolder = null; // null = all sounds, "" = top level, else "a/b"

function usage() {
  const used = {};
  for (const e of Object.values(config.hooks)) for (const n of e.sounds || []) used[n] = (used[n] || 0) + 1;
  for (const v of Object.values(config.voices)) used[v.sound] = (used[v.sound] || 0) + 1;
  return used;
}

const cleanPart = (p) => p.toLowerCase().replace(/[^a-z0-9_ .-]+/g, "_").replace(/^[ .-]+/, "").slice(0, 40) || "folder";
const dirOf = (rel) => rel.split("/").slice(0, -1).map(cleanPart).join("/");
const joinFolder = (...parts) => parts.filter(Boolean).join("/");

async function moveSounds(names, folder) {
  try {
    const res = await api("/api/move", { method: "POST", json: { names, folder } });
    for (const s of catalog.sounds) if (res.moved.includes(s.name)) s.folder = folder;
    toast(`Moved ${res.moved.length} sound(s) to ${folder || "the top level"}`);
  } catch (e) { toast(e.message); }
  renderLibrary();
}

// deleting: the files go to editor_trash/sounds (not lost), and whatever
// used them stops using them
async function deleteSounds(names) {
  const used = usage();
  const inUse = names.filter((n) => used[n]);
  const what = names.length === 1 ? `"${names[0]}"` : `${names.length} sounds`;
  const warn = inUse.length ? `\n\nIt's used ${inUse.reduce((t, n) => t + used[n], 0)}× - those hooks and voice lines will stop playing it.` : "";
  if (!confirm(`Delete ${what}?${warn}\n\n(The file goes to editor_trash/sounds, so it can be put back by hand.)`)) return;
  try {
    const res = await api("/api/sounds/delete", { method: "POST", json: { names } });
    catalog.sounds = catalog.sounds.filter((s) => !res.deleted.includes(s.name));
    // (the saved settings were cleaned up too; this keeps any unsaved
    // changes made here)
    for (const e of Object.values(config.hooks)) if (e.sounds) e.sounds = e.sounds.filter((n) => !res.deleted.includes(n));
    for (const [k, v] of Object.entries(config.voices)) if (res.deleted.includes(v.sound)) delete config.voices[k];
    toast(`Deleted ${res.deleted.length} sound(s)` + (res.unhooked ? `, removed from ${res.unhooked} place(s) that used them` : ""));
  } catch (e) { toast(e.message); }
  renderLibrary();
}

function folderButton(label, folder, depth, count) {
  const b = el("button", { class: "folder", "aria-pressed": String(libFolder === folder),
    style: `padding-left:${10 + depth * 14}px`,
    onclick: () => { libFolder = folder; renderLibrary(); } },
  el("span", {}, label), el("span", { class: "n" }, String(count)));
  if (folder !== null) {
    b.addEventListener("dragover", (e) => { if (e.dataTransfer.types.includes("text/x-nhv-sound")) { e.preventDefault(); b.classList.add("drop"); } });
    b.addEventListener("dragleave", () => b.classList.remove("drop"));
    b.addEventListener("drop", (e) => {
      const name = e.dataTransfer.getData("text/x-nhv-sound");
      b.classList.remove("drop");
      if (name) { e.preventDefault(); moveSounds([name], folder); }
    });
  }
  return b;
}

function renderFolders() {
  const box = $("#libFolders");
  box.textContent = "";
  const counts = {};
  for (const s of catalog.sounds) counts[s.folder || ""] = (counts[s.folder || ""] || 0) + 1;
  const deep = (f) => Object.entries(counts).reduce((n, [k, c]) => n + (k === f || k.startsWith(f + "/") ? c : 0), 0);
  box.append(folderButton("All sounds", null, 0, catalog.sounds.length),
    folderButton("Top level", "", 0, counts[""] || 0));
  for (const f of catalog.folders) {
    const parts = f.split("/");
    box.append(folderButton(parts[parts.length - 1], f, parts.length, deep(f)));
  }
  if (libFolder && !deep(libFolder) && catalog.folders.includes(libFolder)) {
    box.append(el("button", { class: "add", onclick: async () => {
      try {
        await api("/api/folders/delete", { method: "POST", json: { folder: libFolder } });
        catalog.folders = catalog.folders.filter((f) => f !== libFolder && !f.startsWith(libFolder + "/"));
        libFolder = null;
        renderLibrary();
      } catch (e) { toast(e.message); }
    } }, "Delete this empty folder"));
  }
}

function renderLibrary() {
  renderFolders();
  const q = $("#libSearch").value.trim().toLowerCase();
  const used = usage();
  const list = $("#libList");
  list.textContent = "";
  const folderOptions = ["", ...catalog.folders];
  let n = 0;
  for (const s of catalog.sounds) {
    const f = s.folder || "";
    if (libFolder !== null && !q && f !== libFolder) continue;
    if (libFolder !== null && q && !(f === libFolder || f.startsWith(libFolder + "/"))) continue;
    if (q && !(s.name.includes(q) || f.includes(q))) continue;
    n++;
    const move = el("select", { class: "move", "aria-label": "Move " + s.name + " to folder",
      onchange: (e) => moveSounds([s.name], e.target.value) },
    ...folderOptions.map((o) => el("option", { value: o, selected: o === f || null }, o || "(top level)")));
    const card = el("div", { class: "card" + (used[s.name] ? "" : " unused"), draggable: "true" },
      el("button", { class: "icon", "aria-label": "Play " + s.name, onclick: () => play(s.name) }, "▶"),
      el("div", { class: "info" }, el("div", { class: "name" }, s.name, s.midi ? el("span", { class: "folder-tag" }, " MIDI") : null),
        el("div", { class: "uses" }, used[s.name] ? `used ${used[s.name]}×` : "not used yet"),
        libFolder === null || q ? el("div", { class: "folder-tag" }, f || "(top level)") : null),
      move,
      el("button", { class: "icon danger", title: "Delete", "aria-label": "Delete " + s.name,
        onclick: () => deleteSounds([s.name]) }, "✕"));
    card.addEventListener("dragstart", (e) => e.dataTransfer.setData("text/x-nhv-sound", s.name));
    list.append(card);
  }
  const where = libFolder === null ? "all folders" : libFolder || "the top level";
  $("#libCount").textContent = `${n} shown (${where}) · ${catalog.sounds.length} sounds in ${catalog.folders.length} folders`;
}

async function newFolder() {
  const name = prompt("New folder name" + (libFolder ? ` (inside ${libFolder})` : ""));
  if (!name) return;
  try {
    const res = await api("/api/folders", { method: "POST", json: { folder: joinFolder(libFolder || "", cleanPart(name)) } });
    addFolderPath(res.folder);
    libFolder = res.folder;
    renderLibrary();
  } catch (e) { toast(e.message); }
}

// files dropped from Explorer, folders included (keeps their structure)
async function droppedFiles(dt) {
  const out = [];
  const walk = (entry, path) => new Promise((resolve) => {
    if (entry.isFile) {
      entry.file((f) => { out.push({ file: f, path }); resolve(); }, resolve);
    } else if (entry.isDirectory) {
      const reader = entry.createReader();
      const sub = joinFolder(path, cleanPart(entry.name));
      const all = [];
      const read = () => reader.readEntries(async (batch) => {
        if (!batch.length) {
          for (const e of all) await walk(e, sub);
          resolve();
        } else { all.push(...batch); read(); }
      }, resolve);
      read();
    } else resolve();
  });
  const entries = [...dt.items].map((i) => i.webkitGetAsEntry && i.webkitGetAsEntry()).filter(Boolean);
  if (!entries.length) return [...dt.files].map((f) => ({ file: f, path: "" }));
  for (const e of entries) await walk(e, "");
  return out;
}

// items: [{file, path}] where path is a sub-folder (relative to the current one)
async function addFiles(items) {
  items = items.filter((it) => AUDIO_EXT.test(it.file.name));
  if (!items.length) return toast("No audio files found there");
  const base = libFolder || "";
  let done = 0, failed = 0;
  for (const it of items) {
    toast(`Importing ${done + failed + 1} of ${items.length}: ${it.file.name}`);
    try {
      await upload(it.file, baseName(it.file.name), joinFolder(base, it.path));
      done++;
    } catch (e) { failed++; console.warn(it.file.name, e); }
  }
  renderLibrary();
  toast(`Imported ${done} file(s)` + (failed ? `, ${failed} failed` : ""));
}

// ------------------------------------------------------------ wiring
document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => {
  document.querySelectorAll(".tabs button").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
  document.querySelectorAll(".tab").forEach((t) => (t.hidden = t.id !== "tab-" + b.dataset.tab));
  if (b.dataset.tab === "library") renderLibrary();
  if (b.dataset.tab === "casting") VoiceGen.render();
  if (b.dataset.tab === "blocks") Blocks.render();
  if (b.dataset.tab === "effects") Effects.render();
  if (b.dataset.tab === "sky") Sky.render();
  history.replaceState(null, "", "#" + b.dataset.tab);
}));
$("#saveBtn").addEventListener("click", save);
$("#hookSearch").addEventListener("input", renderHooks);
$("#hookUnassigned").addEventListener("change", renderHooks);
for (const id of ["#voiceSearch", "#voiceCategory", "#voiceSpeaker", "#voiceState"]) {
  $(id).addEventListener("input", () => { voicePage = 0; renderVoices(); });
}
$("#exportScript").addEventListener("click", exportScript);
$("#genShown").addEventListener("click", () => VoiceGen.bulk("generate", filteredDialogue()));
$("#reprocShown").addEventListener("click", () => VoiceGen.bulk("process", filteredDialogue()));
$("#libSearch").addEventListener("input", renderLibrary);
$("#libUpload").addEventListener("change", (e) => { addFiles([...e.target.files].map((f) => ({ file: f, path: "" }))); e.target.value = ""; });
$("#libFolderUpload").addEventListener("change", (e) => {
  addFiles([...e.target.files].map((f) => ({ file: f, path: dirOf(f.webkitRelativePath || "") })));
  e.target.value = "";
});
$("#libNewFolder").addEventListener("click", newFolder);
const lib = $("#libList");
lib.addEventListener("dragover", (e) => { if (e.dataTransfer.types.includes("Files")) { e.preventDefault(); lib.classList.add("drop-target"); } });
lib.addEventListener("dragleave", () => lib.classList.remove("drop-target"));
lib.addEventListener("drop", async (e) => {
  if (!e.dataTransfer.types.includes("Files")) return;
  e.preventDefault();
  lib.classList.remove("drop-target");
  addFiles(await droppedFiles(e.dataTransfer));
});
$("#pickerClose").addEventListener("click", closePicker);
$("#pickerSearch").addEventListener("input", renderPicker);
$("#picker").addEventListener("click", (e) => { if (e.target.id === "picker") closePicker(); });
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !$("#picker").hidden) closePicker();
  if (e.key === "Escape" && !$("#confirm").hidden) $("#confirmNo").click();
  if ((e.ctrlKey || e.metaKey) && e.key === "s") { e.preventDefault(); if (dirty) save(); }
});
window.addEventListener("beforeunload", (e) => {
  if (dirty || Blocks.isDirty() || Effects.isDirty() || Sky.isDirty()) { e.preventDefault(); e.returnValue = ""; }
});

load().catch((e) => toast("Could not load: " + e.message));
Blocks.load().catch((e) => toast("Could not load blocks: " + e.message));
$("#blkSave").addEventListener("click", () => Blocks.save());
Effects.load().catch((e) => toast("Could not load effects: " + e.message));
$("#fxSave").addEventListener("click", () => Effects.save());
Sky.load().catch((e) => toast("Could not load skies: " + e.message));
$("#skySave").addEventListener("click", () => Sky.save());
// open a tab from the address (e.g. .../#blocks)
{
  const t = location.hash.slice(1);
  const btn = t && document.querySelector(`.tabs button[data-tab="${t}"]`);
  if (btn) btn.click();
}

// keep the server running while this page is open; it stops itself a few
// seconds after the page closes
setInterval(() => api("/api/ping").catch(() => toast("The editor server has stopped — run the editor again to keep working.")), 30000);
window.addEventListener("pagehide", () => navigator.sendBeacon("/api/bye"));
