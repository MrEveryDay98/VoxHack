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
  let sheetQuery = "";

  const touch = () => { dirty = true; $("#blkSave").disabled = false; $("#blkDirty").hidden = false; };

  async function load() {
    const res = await api("/api/blocks");
    data = res.data;
    textures = res.textures;
    sheet = res.sheet;
    const b = data.blocks[sel];
    texTab = b && b.texture && b.texture.file ? "file" : "sheet";
    render();
  }

  async function save() {
    try {
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
    if (t && t.file) {
      d.style.backgroundImage = `url(/blocktex/${t.file})`;
      d.style.backgroundSize = "100% 100%";
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

  function texCss(t) {
    // CSS for a face of the preview (background stretched over the face)
    if (t && t.file) return `background-image:url(/blocktex/${t.file});background-size:100% 100%;`;
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
    const face = (w, h, transform, extra = "") =>
      el("div", { class: "blk-face", style: `width:${w}px;height:${h}px;margin:${-h / 2}px 0 0 ${-w / 2}px;transform:${transform};${tex}${extra}` });
    const shape = b.shape || "cube";
    const s = (b.scale || 1) * S;
    if (shape === "cube" || shape === "slab" || shape === "pane") {
      const h = shape === "slab" ? S / 2 : S;
      const d = shape === "pane" ? S / 8 : S;
      const y = shape === "slab" ? S / 4 : 0;
      rig.append(
        face(S, h, `translateY(${y}px) translateZ(${d / 2}px)`),
        face(S, h, `translateY(${y}px) rotateY(180deg) translateZ(${d / 2}px)`),
        face(d, h, `translateY(${y}px) rotateY(90deg) translateZ(${S / 2}px)`),
        face(d, h, `translateY(${y}px) rotateY(-90deg) translateZ(${S / 2}px)`),
        face(S, d, `translateY(${y - h / 2}px) rotateX(90deg)`),
        face(S, d, `translateY(${y + h / 2}px) rotateX(-90deg)`));
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

  function texturePicker(b) {
    const box = el("div", { class: "blk-texpick" });
    const tabs = el("div", { class: "chips" },
      ...[["sheet", "Sprite sheet"], ["file", "Your pictures"]].map(([k, l]) =>
        el("button", { class: "chip", "aria-pressed": String(texTab === k), onclick: () => { texTab = k; render(); } }, l)));
    box.append(tabs);
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
          if (b.texture && b.texture.sheet === i) cell.classList.add("on");
          cell.onclick = () => { b.texture = { sheet: i }; touch(); render(); };
          grid.append(cell);
        }
        if (!shown) grid.append(el("p", { class: "muted" }, "No sprites match."));
      };
      drawGrid();
      box.append(q, grid);
    } else {
      const grid = el("div", { class: "blk-grid big" });
      for (const f of textures) {
        const cell = el("div", { class: "blk-file" + (b.texture && b.texture.file === f ? " on" : ""), role: "button", tabindex: 0,
          onclick: () => { b.texture = { file: f }; touch(); render(); } },
        texView({ file: f }, 48), el("small", {}, f));
        grid.append(cell);
      }
      const up = el("input", { type: "file", accept: "image/png", hidden: true, onchange: async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        try {
          const res = await api("/api/blocks/texture?name=" + encodeURIComponent(file.name), { method: "POST", body: file });
          if (!textures.includes(res.file)) textures.push(res.file);
          b.texture = { file: res.file };
          touch(); render();
        } catch (err) { toast(err.message); }
      } });
      box.append(el("p", { class: "muted" }, "PNG pictures in mods/nhv_blocks/textures. Use 16×16 for the NetHack look; transparent pixels are see-through."),
        grid, el("label", { class: "button" }, "Upload a PNG…", up));
    }
    return box;
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
          field("Light", num("light", 0, 14, 1), "0 = none, 14 = brightest"),
          el("h4", {}, "Damage"),
          el("div", { class: "inline" },
            field("When you step in", text("damage", "e.g. 1d4", "7em")),
            field("Again every (s)", num("repeat", 0, 60, 0.5), "0 = only on entering"),
            field("Cause of death", text("cause", "sharp spikes"), "“killed by …”")))),
      el("h4", {}, "Texture"), texturePicker(b));
  }

  function render() {
    const root = $("#blocksBody");
    if (!root) return;
    if (sel >= data.blocks.length) sel = Math.max(0, data.blocks.length - 1);
    const list = el("div", { class: "blk-list" },
      ...data.blocks.map((b, i) => el("button", { class: "folder blk-item", "aria-pressed": String(i === sel),
        onclick: () => { sel = i; texTab = b.texture && b.texture.file ? "file" : "sheet"; render(); } },
      texView(b.texture, 24), el("span", {}, b.name || b.id))),
      el("button", { class: "add", onclick: () => {
        let n = 1;
        while (data.blocks.some((b) => b.id === "block" + n)) n++;
        data.blocks.push({ id: "block" + n, name: "New block", shape: "cube", texture: {}, scale: 1, light: 0, damage: "", repeat: 0, cause: "" });
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
    root.replaceChildren(el("div", { class: "blk-layout" }, list,
      b ? el("div", {}, actions, editor(b)) : el("p", { class: "muted" }, "No blocks yet: make one with “+ New block”.")));
  }

  return { load, save, render, isDirty: () => dirty };
})();
