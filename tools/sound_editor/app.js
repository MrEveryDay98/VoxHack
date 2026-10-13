// NetHack Voxel sound & voice editor.
"use strict";

const GROUPS = {
  nethack: "NetHack sounds", events: "Events", traps: "Traps", game: "Game",
};
const MASTERS = [["effects", "Effects"], ["music", "Music"], ["voices", "Voices"]];
const PAGE = 60;

let catalog = { hooks: [], dialogue: [], sounds: [] };
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

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), 2600);
}

function markDirty() {
  dirty = true;
  $("#dirty").hidden = false;
  $("#saveBtn").disabled = false;
}

function play(name) {
  if (audio) audio.pause();
  audio = new Audio(`/sounds/${name}.ogg`);
  audio.play().catch(() => toast("Could not play " + name));
}

// ------------------------------------------------------------ loading/saving
async function load() {
  const [cat, cfg] = await Promise.all([
    fetch("/api/catalog").then((r) => r.json()),
    fetch("/api/config").then((r) => r.json()),
  ]);
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
  renderVoices();
  renderLibrary();
}

async function save() {
  const r = await fetch("/api/config", { method: "PUT", body: JSON.stringify(config, null, 1) });
  if (!r.ok) return toast("Saving failed");
  dirty = false;
  $("#dirty").hidden = true;
  $("#saveBtn").disabled = true;
  toast("Saved — the game picks it up in a couple of seconds");
}

async function upload(file, name) {
  const r = await fetch(`/api/upload?name=${encodeURIComponent(name)}&filename=${encodeURIComponent(file.name)}`,
    { method: "POST", body: file });
  const res = await r.json();
  if (!r.ok) throw new Error(res.error || "upload failed");
  if (!catalog.sounds.find((s) => s.name === res.name)) {
    catalog.sounds.push({ name: res.name, size: file.size });
    catalog.sounds.sort((a, b) => a.name.localeCompare(b.name));
  }
  return res.name;
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
function openPicker(title, cb) {
  pickerCallback = cb;
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
    if (q && !s.name.includes(q)) continue;
    list.append(el("div", { class: "pick" },
      el("button", { class: "icon", "aria-label": "Play " + s.name, onclick: () => play(s.name) }, "▶"),
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
  }) }, isMusic ? (entry ? "Change…" : "+ Choose music") : "+ Add sound"));

  const controls = el("div", { class: "controls" });
  if (entry) {
    const vol = el("span", {}, entry.volume ?? 100);
    controls.append("Volume", el("input", { type: "range", min: 0, max: 150, value: entry.volume ?? 100,
      "aria-label": "Volume", oninput: (e) => { entry.volume = +e.target.value; vol.textContent = e.target.value; markDirty(); } }), vol);
    if (!isMusic) {
      const pv = el("span", {}, Math.round((entry.pitch_var ?? 0) * 100) + "%");
      controls.append("Pitch ±", el("input", { type: "range", min: 0, max: 30, value: Math.round((entry.pitch_var ?? 0) * 100),
        "aria-label": "Pitch variation", oninput: (e) => { entry.pitch_var = +e.target.value / 100; pv.textContent = e.target.value + "%"; markDirty(); } }), pv);
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
    if (q && !(d.text.toLowerCase().includes(q) || d.id.toLowerCase().includes(q) || d.speaker.toLowerCase().includes(q))) return false;
    return true;
  });
}

function highlight(text) {
  const frag = document.createDocumentFragment();
  const re = /%[-0-9.]*l?[sdcuix]|%[a-zA-Z]{1,2}/g;
  let last = 0, m;
  while ((m = re.exec(text))) {
    frag.append(text.slice(last, m.index), el("mark", { title: "filled in during play" }, m[0]));
    last = m.index + m[0].length;
  }
  frag.append(text.slice(last));
  return frag;
}

function voiceRow(d) {
  const v = config.voices[d.id];
  const row = el("div", { class: "vrow" + (v ? " voiced" : "") });
  const voiceName = "voice_" + d.id.toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  const attach = async (file) => {
    try {
      toast("Converting " + file.name + "…");
      const name = await upload(file, voiceName.slice(0, 80));
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
    el("div", { class: "text" }, highlight(d.text)), voice);
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
function usage() {
  const used = {};
  for (const e of Object.values(config.hooks)) for (const n of e.sounds || []) used[n] = (used[n] || 0) + 1;
  for (const v of Object.values(config.voices)) used[v.sound] = (used[v.sound] || 0) + 1;
  return used;
}

function renderLibrary() {
  const q = $("#libSearch").value.trim().toLowerCase();
  const used = usage();
  const list = $("#libList");
  list.textContent = "";
  let n = 0;
  for (const s of catalog.sounds) {
    if (q && !s.name.includes(q)) continue;
    n++;
    list.append(el("div", { class: "card" + (used[s.name] ? "" : " unused") },
      el("button", { class: "icon", "aria-label": "Play " + s.name, onclick: () => play(s.name) }, "▶"),
      el("div", {}, el("div", { class: "name" }, s.name),
        el("div", { class: "uses" }, used[s.name] ? `used ${used[s.name]}×` : "not used yet"))));
  }
  $("#libCount").textContent = `${n} of ${catalog.sounds.length} sounds`;
}

async function addFiles(files) {
  for (const f of files) {
    try {
      toast("Converting " + f.name + "…");
      await upload(f, baseName(f.name));
    } catch (e) { toast(e.message); }
  }
  renderLibrary();
  toast("Added " + files.length + " file(s)");
}

// ------------------------------------------------------------ wiring
document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => {
  document.querySelectorAll(".tabs button").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
  document.querySelectorAll(".tab").forEach((t) => (t.hidden = t.id !== "tab-" + b.dataset.tab));
  if (b.dataset.tab === "library") renderLibrary();
}));
$("#saveBtn").addEventListener("click", save);
$("#hookSearch").addEventListener("input", renderHooks);
$("#hookUnassigned").addEventListener("change", renderHooks);
for (const id of ["#voiceSearch", "#voiceCategory", "#voiceSpeaker", "#voiceState"]) {
  $(id).addEventListener("input", () => { voicePage = 0; renderVoices(); });
}
$("#exportScript").addEventListener("click", exportScript);
$("#libSearch").addEventListener("input", renderLibrary);
$("#libUpload").addEventListener("change", (e) => addFiles([...e.target.files]));
const lib = $("#tab-library");
lib.addEventListener("dragover", (e) => { e.preventDefault(); lib.classList.add("drop-target"); });
lib.addEventListener("dragleave", () => lib.classList.remove("drop-target"));
lib.addEventListener("drop", (e) => { e.preventDefault(); lib.classList.remove("drop-target"); addFiles([...e.dataTransfer.files]); });
$("#pickerClose").addEventListener("click", closePicker);
$("#pickerSearch").addEventListener("input", renderPicker);
$("#picker").addEventListener("click", (e) => { if (e.target.id === "picker") closePicker(); });
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !$("#picker").hidden) closePicker();
  if ((e.ctrlKey || e.metaKey) && e.key === "s") { e.preventDefault(); if (dirty) save(); }
});
window.addEventListener("beforeunload", (e) => { if (dirty) { e.preventDefault(); e.returnValue = ""; } });

load().catch((e) => toast("Could not load: " + e.message));
