// Block editor (the Blocks tab): blocks made here become "nhv:x_<id>" in
// the game and the prefab editor's palette (after a restart).
"use strict";

const Blocks = (() => {
  const SHAPES = [
    ["cube", "Cube"], ["x", "Crossed sprites (like grass)"], ["floor", "Flat on the floor"],
    ["slab", "Slab"], ["pane", "Pane"], ["object", "3D object (extruded sprite)"], ["invisible", "Invisible"],
  ];
  let data = { version: 1, blocks: [] };
  let textures = [];
  let sheet = { cols: 48, rows: 25, names: {} };
  let sel = 0;
  let dirty = false;
  let texTab = "sheet";
  let anims = {}; // picture -> {frames, length}: the animated ones
  let gameTex = []; // the game's own texture folders: [{folder, files}]
  let sheetQuery = "";
  // the game's own blocks ("Game blocks" tab)
  let mode = "custom";      // "custom" | "game"
  let game = null;          // catalog the game wrote (null: not yet)
  let overrides = {};       // block name -> changed fields
  let gameSel = null;
  let gameQuery = "";
  let gameDirty = false;

  const touch = () => { dirty = true; $("#blkSave").disabled = false; $("#blkDirty").hidden = false; };

  async function load() {
    const res = await api("/api/blocks");
    data = res.data;
    textures = res.textures;
    anims = res.anims || {};
    gameTex = res.gametex || [];
    sheet = res.sheet;
    game = res.game;
    overrides = res.overrides || {};
    // (a block given an animated picture without its frames - picked
    // before pictures brought them along: it gets them, to be saved)
    let fixed = false;
    for (const blk of data.blocks) {
      for (const k of ["texture", "texture_top", "texture_bottom"]) {
        const a = blk[k] && blk[k].file && anims[blk[k].file];
        if (a && blk[k].frames !== a.frames) {
          Object.assign(blk[k], a);
          fixed = true;
        }
      }
    }
    const b = data.blocks[sel];
    texTab = b && b.texture && b.texture.file ? "file" : "sheet";
    render();
    if (fixed) {
      touch();
      toast("Some blocks' animated pictures were missing their frames: fixed. Save blocks to keep it.");
    }
  }

  async function save() {
    try {
      if (gameDirty) {
        const r = await api("/api/blocks/overrides", { method: "PUT", json: { blocks: overrides } });
        overrides = r.overrides;
        gameDirty = false;
      }
      const res = await api("/api/blocks", { method: "PUT", json: data });
      data.blocks = res.blocks;
      dirty = false;
      $("#blkSave").disabled = true;
      $("#blkDirty").hidden = true;
      toast("Saved. Restart the game or the prefab editor to use the changes.");
      render();
    } catch (e) { toast("Not saved: " + e.message); }
  }

  // ------------------------------------------------------------ textures
  function texUrl(t) {
    if (!t) return null;
    if (t.file) return `/blocktex/${t.file}`;
    return null;
  }

  // an element showing a texture (sheet sprite or file) at size px
  function texView(t, size) {
    const d = el("div", { class: "tex", style: `width:${size}px;height:${size}px` });
    if (t && (t.file || t.gamefile)) {
      d.style.backgroundImage = t.file ? `url(/blocktex/${t.file})` : `url(/gametex/${t.gamefile})`;
      // (an animation: its frames in turn)
      d.style.backgroundSize = `100% ${(t.frames || 1) * 100}%`;
      d.style.backgroundPosition = "0 0";
      if (t.frames > 1) d.style.animation = frameAnim(t);
    } else if (t && t.color) {
      d.style.background = t.color;
    } else if (t && t.sheet != null) {
      const k = size / 16;
      d.style.backgroundImage = "url(/sheet.png)";
      d.style.backgroundSize = `${sheet.cols * 16 * k}px ${sheet.rows * 16 * k}px`;
      d.style.backgroundPosition = `-${(t.sheet % sheet.cols) * 16 * k}px -${Math.floor(t.sheet / sheet.cols) * 16 * k}px`;
    } else {
      d.classList.add("none");
    }
    return d;
  }

  // an animated texture (frames stacked top to bottom): steps through them,
  // one loop every t.length seconds (as the game plays it)
  function frameAnim(t) {
    return `nhvframes ${t.length || 1}s steps(${t.frames}, jump-none) infinite`;
  }

  function texCss(t) {
    // CSS for a face of the preview (background stretched over the face)
    if (t && t.file) return `background-image:url(/blocktex/${t.file});background-size:100% ${(t.frames || 1) * 100}%;background-position:0 0;`
      + (t.frames > 1 ? `animation:${frameAnim(t)};` : "");
    if (t && t.gamefile) return `background-image:url(/gametex/${t.gamefile});background-size:100% 100%;`;
    if (t && t.color) return `background:${t.color};`;
    if (t && t.sheet != null) {
      const c = sheet.cols, r = sheet.rows;
      const x = t.sheet % c, y = Math.floor(t.sheet / c);
      return `background-image:url(/sheet.png);background-size:${c * 100}% ${r * 100}%;`
        + `background-position:${(x / (c - 1)) * 100}% ${(y / (r - 1)) * 100}%;`;
    }
    return "background:repeating-conic-gradient(#3a3a46 0 25%,#2a2a33 0 50%) 0 0/16px 16px;";
  }

  // ------------------------------------------------------------ preview
  function preview(b) {
    const S = 140; // a block, in pixels
    const scene = el("div", { class: "blk-scene" });
    const rig = el("div", { class: "blk-rig" });
    scene.append(rig);
    const tex = texCss(b.texture);
    const topTex = b.texture_top ? texCss(b.texture_top) : tex;
    const botTex = b.texture_bottom ? texCss(b.texture_bottom) : topTex;
    const face = (w, h, transform, extra = "", t = tex) =>
      el("div", { class: "blk-face", style: `width:${w}px;height:${h}px;margin:${-h / 2}px 0 0 ${-w / 2}px;transform:${transform};${t}${extra}` });
    const shape = b.shape || "cube";
    const s = (b.scale || 1) * S;
    const bf = b.backfaces || {};
    const hid = b.hidden || {};
    const show = (side) => (hid[side] ? "display:none" : bf[side] ? "backface-visibility:visible;opacity:.92" : "");
    if (shape === "cube" || shape === "slab" || shape === "pane") {
      const h = shape === "slab" ? S / 2 : S;
      const d = shape === "pane" ? S / 8 : S;
      const y = shape === "slab" ? S / 4 : 0;
      rig.append(
        face(S, h, `translateY(${y}px) translateZ(${d / 2}px)`, show("south")),
        face(S, h, `translateY(${y}px) rotateY(180deg) translateZ(${d / 2}px)`, show("north")),
        face(d, h, `translateY(${y}px) rotateY(90deg) translateZ(${S / 2}px)`, show("east")),
        face(d, h, `translateY(${y}px) rotateY(-90deg) translateZ(${S / 2}px)`, show("west")),
        face(S, d, `translateY(${y - h / 2}px) rotateX(90deg)`, show("top"), topTex),
        face(S, d, `translateY(${y + h / 2}px) rotateX(-90deg)`, show("bottom"), botTex));
    } else if (shape === "x") {
      const y = (S - s) / 2;
      rig.append(face(s * 1.41, s, `translateY(${y}px) rotateY(45deg)`, "backface-visibility:visible"),
        face(s * 1.41, s, `translateY(${y}px) rotateY(-45deg)`, "backface-visibility:visible"));
    } else if (shape === "floor") {
      rig.append(face(S, S, `translateY(${S / 2 - 2}px) rotateX(90deg)`, "backface-visibility:visible"));
    } else if (shape === "object") {
      for (let i = 0; i < 6; i++) {
        rig.append(face(s, s, `translateY(${(S - s) / 2}px) translateZ(${(i - 2.5) * 1.6}px)`,
          i > 0 && i < 5 ? "filter:brightness(0.65)" : ""));
      }
    } else {
      rig.append(el("div", { class: "blk-face blk-ghost", style: `width:${S}px;height:${S}px;margin:${-S / 2}px 0 0 ${-S / 2}px` }));
    }
    // the floor it stands on
    rig.append(el("div", { class: "blk-ground", style: `width:${S * 2}px;height:${S * 2}px;margin:${-S}px 0 0 ${-S}px;transform:translateY(${S / 2}px) rotateX(90deg)` }));
    return scene;
  }

  // ------------------------------------------------------------ form
  function field(label, input, hint) {
    return el("label", { class: "blk-field" }, el("span", {}, label), input,
      hint ? el("small", { class: "muted" }, hint) : null);
  }

  function texturePicker(b, key = "texture") {
    const box = el("div", { class: "blk-texpick" });
    const tabs = el("div", { class: "chips" },
      ...[["sheet", "Sprite sheet"], ["file", "Your pictures"], ["gen", "Generate"]].map(([k, l]) =>
        el("button", { class: "chip", "aria-pressed": String(texTab === k), onclick: () => { texTab = k; render(); } }, l)));
    box.append(tabs);
    if (texTab === "gen") {
      // (saved as one of your pictures, and used for this block)
      box.append(TexGen.panel((t) => {
        if (!textures.includes(t.file)) textures.push(t.file);
        if (t.frames > 1) anims[t.file] = { frames: t.frames, length: t.length };
        else delete anims[t.file];
        b[key] = t; touch(); render();
      }));
      return box;
    }
    if (texTab === "sheet") {
      const q = el("input", { type: "search", placeholder: "Search sprites (e.g. spike, door, tree)…", value: sheetQuery,
        oninput: (e) => { sheetQuery = e.target.value; drawGrid(); } });
      const grid = el("div", { class: "blk-grid" });
      const drawGrid = () => {
        grid.textContent = "";
        const qq = sheetQuery.trim().toLowerCase();
        const n = sheet.cols * sheet.rows;
        let shown = 0;
        for (let i = 0; i < n && shown < 600; i++) {
          const name = sheet.names[i];
          if (!name) continue;
          if (qq && !name.toLowerCase().includes(qq)) continue;
          shown++;
          const cell = texView({ sheet: i }, 32);
          cell.title = `${i}: ${name}`;
          cell.tabIndex = 0;
          cell.setAttribute("role", "button");
          if (b[key] && b[key].sheet === i) cell.classList.add("on");
          cell.onclick = () => { b[key] = { sheet: i }; touch(); render(); };
          grid.append(cell);
        }
        if (!shown) grid.append(el("p", { class: "muted" }, "No sprites match."));
      };
      drawGrid();
      box.append(q, grid);
    } else {
      const grid = el("div", { class: "blk-grid big" });
      for (const f of textures) {
        // (an animated picture brings its frames along)
        const t = Object.assign({ file: f }, anims[f] || {});
        const cell = el("div", { class: "blk-file" + (b[key] && b[key].file === f ? " on" : ""), role: "button", tabindex: 0,
          onclick: () => { b[key] = Object.assign({}, t); touch(); render(); } },
        texView(t, 48), el("small", {}, f));
        grid.append(cell);
      }
      const up = el("input", { type: "file", accept: "image/png", hidden: true, onchange: async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        try {
          const res = await api("/api/blocks/texture?name=" + encodeURIComponent(file.name), { method: "POST", body: file });
          if (!textures.includes(res.file)) textures.push(res.file);
          b[key] = Object.assign({ file: res.file }, anims[res.file] || {});
          touch(); render();
        } catch (err) { toast(err.message); }
      } });
      // (the game's own texture folders too: nhv_tiles first)
      const more = gameTex.map((g) => {
        const gg = el("div", { class: "blk-grid big" });
        for (const f of g.files) {
          const t = { file: f };
          gg.append(el("div", { class: "blk-file" + (b[key] && b[key].file === f ? " on" : ""), role: "button", tabindex: 0,
            onclick: () => { b[key] = Object.assign({}, t); touch(); render(); } },
          texView(t, 48), el("small", {}, f)));
        }
        return el("div", {}, el("div", { class: "blk-group" }, "mods/" + g.folder + "/textures"), gg);
      });
      box.append(el("p", { class: "muted" }, "PNG pictures: the blocks' own (mods/nhv_blocks/textures, where uploads go) and the game's texture folders. Use 16×16 for the NetHack look; transparent pixels are see-through."),
        el("div", { class: "blk-group" }, "mods/nhv_blocks/textures"), grid,
        el("label", { class: "button" }, "Upload a PNG…", up), ...more);
    }
    return box;
  }

  // which sides are also drawn from behind (seen from inside the block)
  const SIDES = [["top", "Top"], ["bottom", "Bottom"], ["north", "North"], ["south", "South"],
    ["east", "East"], ["west", "West"]];
  // How each side is drawn: normally (from outside), also from behind (seen
  // from inside the block), or not at all. commit(backfaces, hidden) stores
  // the new choice (defaults to the block's own fields).
  function backfaces(b, commit) {
    const bf = Object.assign({}, b.backfaces || {});
    const hid = Object.assign({}, b.hidden || {});
    const done = commit || ((v, h) => { b.backfaces = v; b.hidden = h; touch(); render(); });
    const MODES = [["normal", "Normal"], ["back", "Also from behind"], ["hidden", "Don't draw"]];
    const modeOf = (k) => (hid[k] ? "hidden" : bf[k] ? "back" : "normal");
    const setMode = (k, m) => {
      delete bf[k]; delete hid[k];
      if (m === "back") bf[k] = true;
      if (m === "hidden") hid[k] = true;
    };
    return el("div", {},
      el("h4", {}, "Sides"),
      el("p", { class: "muted", style: "margin:0 0 6px" },
        "Normally a side is drawn from outside only. “Also from behind” draws it from inside the block too (glass cases, cages, panes seen from both sides); “Don't draw” leaves it out (open-topped boxes, see-through sides)."),
      el("div", { class: "blk-sides" }, ...SIDES.map(([k, l]) => el("label", { class: "blk-field" }, el("span", {}, l),
        el("select", { onchange: (e) => { setMode(k, e.target.value); done(bf, hid); } },
          ...MODES.map(([m, ml]) => el("option", { value: m, selected: modeOf(k) === m || null }, ml)))))),
      el("div", { class: "inline" },
        el("button", { class: "small", onclick: () => { SIDES.forEach(([k]) => setMode(k, "back")); done(bf, hid); } }, "All from behind too"),
        el("button", { class: "small", onclick: () => done({}, {}) }, "All normal")));
  }

  function editor(b) {
    const set = (k, v) => { b[k] = v; touch(); render(); };
    const shapeSel = el("select", { onchange: (e) => set("shape", e.target.value) },
      ...SHAPES.map(([k, l]) => el("option", { value: k, selected: (b.shape || "cube") === k || null }, l)));
    const text = (k, ph, w) => el("input", { type: "text", value: b[k] ?? "", placeholder: ph || "", style: w ? `width:${w}` : null,
      onchange: (e) => set(k, e.target.value) });
    const num = (k, min, max, step) => el("input", { type: "number", value: b[k] ?? 0, min, max, step,
      onchange: (e) => set(k, +e.target.value) });
    const check = (k, label) => el("label", { class: "check" },
      el("input", { type: "checkbox", checked: b[k] || null, onchange: (e) => set(k, e.target.checked) }), label);
    return el("div", { class: "blk-editor" },
      el("div", { class: "blk-top" },
        el("div", { class: "blk-preview" }, preview(b),
          el("div", { class: "muted", style: "text-align:center" }, `nhv:x_${b.id || "?"}`)),
        el("div", { class: "blk-props" },
          field("Name", text("name", "Spikes")),
          field("Id", text("id", "spikes"), "letters, digits and _; the block is nhv:x_<id>"),
          field("Shape", shapeSel),
          (b.shape === "x" || b.shape === "object") ? field("Size", num("scale", 0.1, 4, 0.1), "1 = one block") : null,
          el("div", { class: "inline" }, check("solid", "Solid (can't walk through)"), check("climbable", "Climbable")),
          ["cube", "slab", "pane"].includes(b.shape || "cube") ? field("When you place it",
            el("select", { onchange: (e) => set("turns", e.target.value) },
              ...[["", (b.shape || "cube") === "cube" ? "Always the same way" : "Turns (its usual way)"],
                ["south", "Turns: its south side faces you"], ["north", "Turns: its north side faces you"]]
                .map(([v, l]) => el("option", { value: v, selected: (b.turns || "") === v || null }, l))),
            "Like stairs: it turns to the way you're facing as you place it.") : null,
          (b.shape || "cube") === "cube" ? el("div", {}, check("stretch", "Stretch over touching blocks like it"),
            el("small", { class: "muted", style: "display:block" },
              "Like doors: a box of these blocks is drawn as one big block, each side's picture stretched across it.")) : null,
          field("Light", num("light", 0, 14, 1), "0 = none, 14 = brightest"),
          el("h4", {}, "Damage"),
          el("div", { class: "inline" },
            field("When you step in", text("damage", "e.g. 1d4", "7em")),
            field("Again every (s)", num("repeat", 0, 60, 0.5), "0 = only on entering"),
            field("Cause of death", text("cause", "sharp spikes"), "“killed by …”")),
          check("spikes", "Iron spikes (iron boots protect; 1 in 6 are poisoned)"))),
      ["cube", "slab", "pane", "floor"].includes(b.shape || "cube") ? backfaces(b) : null,
      el("h4", {}, "Texture"), endsPicker(b));
  }

  // A cube, slab or pane can have its own top and bottom (a tree trunk's
  // rings, a crate's lid): the same as the sides, one texture for both
  // ends, or each its own. The picker below edits the one chosen.
  let texSide = "texture";
  function endsPicker(b) {
    if (!["cube", "slab", "pane"].includes(b.shape || "cube")) return texturePicker(b);
    const mode = b.texture_bottom ? "each" : b.texture_top ? "ends" : "same";
    const setMode = (m) => {
      if (m === "same") { delete b.texture_top; delete b.texture_bottom; texSide = "texture"; }
      if (m === "ends") { b.texture_top = b.texture_top || Object.assign({}, b.texture || {}); delete b.texture_bottom; texSide = "texture_top"; }
      if (m === "each") {
        b.texture_top = b.texture_top || Object.assign({}, b.texture || {});
        b.texture_bottom = b.texture_bottom || Object.assign({}, b.texture_top);
        texSide = "texture_top";
      }
      touch(); render();
    };
    const choice = el("select", { onchange: (e) => setMode(e.target.value) },
      ...[["same", "Same as the sides"], ["ends", "Their own (top and bottom alike)"], ["each", "Each their own"]]
        .map(([v, l]) => el("option", { value: v, selected: v === mode || null }, l)));
    const sides = [["texture", "Sides"]];
    if (mode === "ends") sides.push(["texture_top", "Top and bottom"]);
    if (mode === "each") sides.push(["texture_top", "Top"], ["texture_bottom", "Bottom"]);
    if (!sides.some(([k]) => k === texSide)) texSide = "texture";
    const chips = el("div", { class: "chips" }, ...sides.map(([k, l]) =>
      el("button", { class: "chip", "aria-pressed": String(texSide === k), onclick: () => { texSide = k; render(); } },
        el("span", { class: "inline" }, texView(b[k], 18), l))));
    return el("div", {},
      el("div", { class: "inline" }, field("Top and bottom", choice), mode !== "same" ? chips : null),
      texturePicker(b, texSide));
  }

  function render() {
    const root = $("#blocksBody");
    if (!root) return;
    const tabs = el("div", { class: "chips", style: "margin-bottom:12px" },
      el("button", { class: "chip", "aria-pressed": String(mode === "custom"), onclick: () => { mode = "custom"; render(); } },
        `Your blocks (${data.blocks.length})`),
      el("button", { class: "chip", "aria-pressed": String(mode === "game"), onclick: () => { mode = "game"; render(); } },
        `Game blocks (${game ? game.length : "?"})`));
    if (mode === "game") {
      root.replaceChildren(tabs, renderGame());
      return;
    }
    if (sel >= data.blocks.length) sel = Math.max(0, data.blocks.length - 1);
    const list = el("div", { class: "blk-list" },
      ...data.blocks.map((b, i) => el("button", { class: "folder blk-item", "aria-pressed": String(i === sel),
        onclick: () => { sel = i; texTab = b.texture && b.texture.file ? "file" : "sheet"; render(); } },
      texView(b.texture, 24), el("span", {}, b.name || b.id))),
      el("button", { class: "add", onclick: () => {
        let n = 1;
        while (data.blocks.some((b) => b.id === "block" + n)) n++;
        data.blocks.push({ id: "block" + n, name: "New block", shape: "cube", texture: {}, scale: 1, light: 0, damage: "", repeat: 0, cause: "", solid: true });
        sel = data.blocks.length - 1; touch(); render();
      } }, "+ New block"));
    const b = data.blocks[sel];
    const actions = b ? el("div", { class: "inline" },
      el("button", { class: "small", onclick: () => {
        const copy = JSON.parse(JSON.stringify(b));
        copy.id = b.id + "_copy"; copy.name = (b.name || b.id) + " copy";
        data.blocks.splice(sel + 1, 0, copy); sel++; touch(); render();
      } }, "Duplicate"),
      el("button", { class: "small", onclick: () => {
        if (!confirm(`Delete the block "${b.name || b.id}"? Prefabs using it will show air there.`)) return;
        data.blocks.splice(sel, 1); touch(); render();
      } }, "Delete")) : null;
    root.replaceChildren(tabs, el("div", { class: "blk-layout" }, list,
      b ? el("div", {}, actions, editor(b)) : el("p", { class: "muted" }, "No blocks yet: make one with “+ New block”.")));
  }

  // ------------------------------------------------------------ game blocks
  const touchGame = () => { gameDirty = true; $("#blkSave").disabled = false; $("#blkDirty").hidden = false; };

  function gameGroup(g) {
    if (["nhv:trigger", "nhv:mpath", "nhv:carve"].includes(g.name)) return "Markers";
    if (g.prop) return "Objects";
    if (g.name.startsWith("nhv:b_")) return "Building blocks";
    if (g.name.startsWith("nhv:editor") || g.name === "nhv:void" || g.name === "nhv:void_floor") return "Editor / internal";
    return "Terrain";
  }

  function gameShape(g) {
    if (g.prop) return "object";
    return { normal: "cube", glasslike: "cube", liquid: "cube", plantlike: "x", airlike: "invisible",
      nodebox: "cube", allfaces: "cube" }[g.drawtype] || "cube";
  }

  // the block as it will be in the game: its own values with your changes on top
  function effective(g) {
    const o = overrides[g.name] || {};
    const has = (k) => o[k] !== undefined;
    return {
      id: g.name.replace(/^nhv:/, ""), name: has("name") ? o.name : g.description,
      shape: gameShape(g), texture: has("texture") ? o.texture : g.look,
      solid: has("solid") ? o.solid : g.solid, climbable: has("climbable") ? o.climbable : g.climbable,
      light: has("light") ? o.light : g.light, damage: o.damage || "", repeat: o.repeat || 0,
      cause: o.cause || "", spikes: o.spikes || false, backfaces: o.backfaces || {}, hidden: o.hidden || {}, scale: 1,
    };
  }

  function renderGame() {
    if (!game) {
      return el("p", { class: "muted" }, "Start the game or the prefab editor once: it writes the list of its blocks for this tab.");
    }
    const q = gameQuery.trim().toLowerCase();
    const groups = {};
    for (const g of game) {
      if (q && !(g.name.includes(q) || (g.description || "").toLowerCase().includes(q))) continue;
      (groups[gameGroup(g)] = groups[gameGroup(g)] || []).push(g);
    }
    if (!gameSel || !game.find((g) => g.name === gameSel)) gameSel = game[0] && game[0].name;
    const list = el("div", { class: "blk-list" },
      el("input", { type: "search", placeholder: "Search blocks…", value: gameQuery,
        oninput: (e) => { gameQuery = e.target.value; render(); $("#blocksBody input[type=search]").focus(); } }));
    for (const name of ["Terrain", "Building blocks", "Objects", "Markers", "Editor / internal"]) {
      if (!groups[name]) continue;
      list.append(el("div", { class: "blk-group" }, name));
      for (const g of groups[name]) {
        const eff = effective(g);
        list.append(el("button", { class: "folder blk-item", "aria-pressed": String(g.name === gameSel),
          onclick: () => { gameSel = g.name; texTab = "sheet"; render(); } },
        texView(eff.texture, 24), el("span", {}, eff.name), overrides[g.name] ? el("span", { class: "blk-changed", title: "changed" }, "●") : null));
      }
    }
    const g = game.find((x) => x.name === gameSel);
    return el("div", { class: "blk-layout" }, list, g ? gameEditor(g) : el("p", {}, ""));
  }

  function gameEditor(g) {
    const o = overrides[g.name] || {};
    const b = effective(g);
    const set = (k, v) => {
      overrides[g.name] = Object.assign(overrides[g.name] || {}, { [k]: v });
      touchGame(); render();
    };
    // the texture picker sets b.texture: record that as a change instead
    const proxy = new Proxy(b, {
      set(target, k, v) { target[k] = v; overrides[g.name] = Object.assign(overrides[g.name] || {}, { [k]: v }); touchGame(); return true; },
    });
    const text = (k, ph, w) => el("input", { type: "text", value: b[k] ?? "", placeholder: ph || "", style: w ? `width:${w}` : null,
      onchange: (e) => set(k, e.target.value) });
    const num = (k, min, max, step) => el("input", { type: "number", value: b[k] ?? 0, min, max, step,
      onchange: (e) => set(k, +e.target.value) });
    const check = (k, label) => el("label", { class: "check" },
      el("input", { type: "checkbox", checked: b[k] || null, onchange: (e) => set(k, e.target.checked) }), label);
    const changed = Object.keys(o).length > 0;
    return el("div", {},
      el("div", { class: "inline" },
        el("code", {}, g.name),
        changed ? el("span", { class: "dirty" }, "changed from the game's default") : el("span", { class: "muted" }, "as in the game"),
        changed ? el("button", { class: "small", onclick: () => { delete overrides[g.name]; touchGame(); render(); } },
          "Reset to the game's default") : null),
      el("div", { class: "blk-editor" },
        el("div", { class: "blk-top" },
          el("div", { class: "blk-preview" }, preview(b),
            el("div", { class: "muted", style: "text-align:center" }, `${g.drawtype}${g.prop ? " (object)" : ""}`)),
          el("div", { class: "blk-props" },
            field("Name", text("name", g.description)),
            field("Shape", el("span", {}, b.shape + " — fixed for the game's own blocks")),
            el("div", { class: "inline" }, check("solid", "Solid (can't walk through)"), check("climbable", "Climbable")),
            field("Light", num("light", 0, 14, 1), "0 = none, 14 = brightest"),
            el("h4", {}, "Damage"),
            el("div", { class: "inline" },
              field("When you step in", text("damage", "e.g. 1d4", "7em")),
              field("Again every (s)", num("repeat", 0, 60, 0.5), "0 = only on entering"),
              field("Cause of death", text("cause", g.description), "“killed by …”")),
            check("spikes", "Iron spikes (iron boots protect; 1 in 6 are poisoned)"))),
        ["cube", "slab", "pane", "floor"].includes(b.shape) && g.drawtype !== "liquid" ? backfaces(b, (v, h) => {
          overrides[g.name] = Object.assign(overrides[g.name] || {}, { backfaces: v, hidden: h });
          touchGame(); render();
        }) : null,
        el("h4", {}, "Texture"), texturePicker(proxy)));
  }

  return { load, save, render, isDirty: () => dirty || gameDirty };
})();
