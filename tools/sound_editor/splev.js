// Special levels (the Special levels tab): a map of every special level,
// for reading - where its hand-built parts (the prefab editor's areas) go,
// and what NetHack makes around them. Each map is one level as NetHack
// built it once (tools/make_splev_templates.py), before any flip: the
// parts in full colour, what NetHack makes around them dimmed and hatched
// (it's different every game), with the level's stairs and the regions
// stairs, branches and arrivals are put in.
"use strict";

const Splev = (() => {
  const T = {
    STONE: 0, VWALL: 1, TRWALL: 11, DBWALL: 12, TREE: 13, SDOOR: 14, SCORR: 15, POOL: 16,
    MOAT: 17, WATER: 18, DRAWBRIDGE_UP: 19, LAVAPOOL: 20, LAVAWALL: 21, IRONBARS: 22,
    DOOR: 23, CORR: 24, ROOM: 25, STAIRS: 26, LADDER: 27, FOUNTAIN: 28, THRONE: 29, SINK: 30,
    GRAVE: 31, ALTAR: 32, ICE: 33, DRAWBRIDGE_DOWN: 34, AIR: 35, CLOUD: 36,
  };
  // terrain: [colour, name]
  const TERRAIN = {};
  const set = (typs, col, name) => typs.forEach((t) => (TERRAIN[t] = [col, name]));
  set([0], "#14151a", "solid rock");
  set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], "#6c7080", "wall");
  set([13], "#3d7a3a", "tree");
  set([14], "#d08a2a", "secret door");
  set([15], "#8a7550", "secret corridor");
  set([16, 17, 18], "#2f62a8", "water");
  set([19, 34], "#8a5a2b", "drawbridge");
  set([20, 21], "#d3561f", "lava");
  set([22], "#93a7b5", "iron bars");
  set([23], "#a8692e", "door");
  set([24], "#8b8677", "corridor");
  set([25], "#cfc9b6", "floor");
  set([26], "#e0a020", "stairs");
  set([27], "#e0a020", "ladder");
  set([28], "#62b4e6", "fountain");
  set([29], "#d8b030", "throne");
  set([30], "#a7b0b8", "sink");
  set([31], "#7c7c7c", "grave");
  set([32], "#b585d6", "altar");
  set([33], "#bfe6f5", "ice");
  set([35], "#6ea4dc", "air");
  set([36], "#c9cdd6", "cloud");
  const PART_COLORS = ["#b77ff0", "#3fc4b0", "#f0c040", "#f07a7a", "#7ab0f0", "#9fdc6a"];
  // level regions (NetHack's lev_region types)
  const REGIONS = {
    0: { col: "#ff6b5b", name: "down stairs go somewhere in here" },
    1: { col: "#5bb0ff", name: "up stairs go somewhere in here" },
    2: { col: "#d36bff", name: "the portal goes somewhere in here" },
    3: { col: "#ffd23f", name: "the branch (stairs or portal to another dungeon) goes in here" },
    4: { col: "#7be07b", name: "you arrive in here when you fall or teleport in" },
    5: { col: "#7be0d0", name: "you arrive in here when you come up (not by stairs)" },
    6: { col: "#c5e07b", name: "you arrive in here when you come down (not by stairs)" },
  };
  const FLIPS = ["never flipped", "may be flipped top to bottom", "may be mirrored left to right",
    "may be mirrored left to right and/or flipped top to bottom"];

  let data = null;
  let loading = null;
  let rendered = false;
  const show = { regions: true, stairs: true, outside: true };

  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  async function load() {
    if (!loading) loading = api("/api/splev").then((d) => (data = d));
    return loading;
  }

  function partAt(lv, x, y) {
    return lv.parts.find((p) => x >= p.x && x < p.x + p.w && y >= p.y && y < p.y + p.h);
  }

  function inRect(r, x, y) {
    return r && x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3];
  }

  // a region's squares: its area minus what's left out (whole level if 0s)
  function regionHas(rg, x, y) {
    const a = rg.area.every((v) => v === 0) ? [1, 0, data.cols - 1, data.rows - 1] : rg.area;
    return inRect(a, x, y) && !inRect(rg.except, x, y);
  }

  function draw(cv, lv) {
    const C = data.cols, R = data.rows;
    const css = (cv.parentElement && cv.parentElement.clientWidth - 28) || 960;
    const s = Math.max(4, Math.floor(css / C));
    const dpr = window.devicePixelRatio || 1;
    cv.width = C * s * dpr;
    cv.height = R * s * dpr;
    cv.style.height = (R * s) + "px";
    cv.style.width = (C * s) + "px";
    const g = cv.getContext("2d");
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.fillStyle = "#0d0e12";
    g.fillRect(0, 0, C * s, R * s);
    for (let y = 0; y < R; y++) {
      for (let x = 1; x < C; x++) {
        const t = lv.typ.charCodeAt(y * C + x) - 48;
        const inside = partAt(lv, x, y);
        if (!inside && !show.outside) continue;
        g.fillStyle = (TERRAIN[t] || ["#ff00ff"])[0];
        g.globalAlpha = inside ? 1 : 0.38;
        g.fillRect(x * s, y * s, s, s);
      }
    }
    g.globalAlpha = 1;
    // what NetHack makes: hatched
    if (show.outside) {
      g.save();
      g.beginPath();
      for (let y = 0; y < R; y++) for (let x = 1; x < C; x++) if (!partAt(lv, x, y)) g.rect(x * s, y * s, s, s);
      g.clip();
      g.strokeStyle = "rgba(0,0,0,.45)";
      g.lineWidth = 1;
      for (let d = -R * s; d < C * s; d += 6) {
        g.beginPath();
        g.moveTo(d, R * s);
        g.lineTo(d + R * s, 0);
        g.stroke();
      }
      g.restore();
    }
    // grid lines inside the parts
    g.strokeStyle = "rgba(0,0,0,.18)";
    g.lineWidth = 1;
    for (const p of lv.parts) {
      for (let x = p.x; x <= p.x + p.w; x++) { g.beginPath(); g.moveTo(x * s + 0.5, p.y * s); g.lineTo(x * s + 0.5, (p.y + p.h) * s); g.stroke(); }
      for (let y = p.y; y <= p.y + p.h; y++) { g.beginPath(); g.moveTo(p.x * s, y * s + 0.5); g.lineTo((p.x + p.w) * s, y * s + 0.5); g.stroke(); }
    }
    // regions: a tint over the squares they can use, outlined
    if (show.regions) {
      lv.regions.forEach((rg) => {
        const col = (REGIONS[rg.t] || { col: "#fff" }).col;
        g.fillStyle = col;
        g.globalAlpha = 0.22;
        for (let y = 0; y < R; y++) for (let x = 1; x < C; x++) if (regionHas(rg, x, y)) g.fillRect(x * s, y * s, s, s);
        g.globalAlpha = 1;
        const a = rg.area.every((v) => v === 0) ? [1, 0, C - 1, R - 1] : rg.area;
        const x1 = Math.max(0, a[0]), y1 = Math.max(0, a[1]), x2 = Math.min(C - 1, a[2]), y2 = Math.min(R - 1, a[3]);
        g.setLineDash([5, 4]);
        g.strokeStyle = col;
        g.lineWidth = 2;
        g.strokeRect(x1 * s + 1, y1 * s + 1, (x2 - x1 + 1) * s - 2, (y2 - y1 + 1) * s - 2);
        g.setLineDash([]);
      });
    }
    // the parts
    lv.parts.forEach((p, i) => {
      const col = PART_COLORS[i % PART_COLORS.length];
      g.strokeStyle = col;
      g.lineWidth = 3;
      g.strokeRect(p.x * s - 1.5, p.y * s - 1.5, p.w * s + 3, p.h * s + 3);
      if (lv.parts.length > 1 && p.w * s >= 14 && p.h * s >= 14) {
        g.fillStyle = col;
        const r = Math.max(7, s * 0.6);
        g.beginPath();
        g.arc(p.x * s + r + 2, p.y * s + r + 2, r, 0, 7);
        g.fill();
        g.fillStyle = "#111";
        g.font = `bold ${Math.round(r * 1.3)}px "Segoe UI", sans-serif`;
        g.textAlign = "center";
        g.textBaseline = "middle";
        g.fillText(String(p.n), p.x * s + r + 2, p.y * s + r + 2.5);
      }
    });
    // stairs, ladders, portals
    if (show.stairs) {
      const mark = (x, y, text, col) => {
        const cx = x * s + s / 2, cy = y * s + s / 2, r = Math.max(6, s * 0.62);
        g.fillStyle = "#111";
        g.beginPath();
        g.arc(cx, cy, r, 0, 7);
        g.fill();
        g.strokeStyle = col;
        g.lineWidth = 2;
        g.stroke();
        g.fillStyle = col;
        g.font = `bold ${Math.round(r * 1.25)}px Consolas, monospace`;
        g.textAlign = "center";
        g.textBaseline = "middle";
        g.fillText(text, cx, cy + 1);
      };
      lv.stairs.forEach((st) => mark(st.x, st.y, st.ladder ? "H" : st.up ? "<" : ">",
        st.branch ? "#ffd23f" : st.up ? "#5bb0ff" : "#ff6b5b"));
      lv.portals.forEach((pt) => mark(pt.x, pt.y, "◇", "#d36bff"));
    }
  }

  function describe(lv, x, y) {
    if (x < 1 || x >= data.cols || y < 0 || y >= data.rows) return "";
    const t = lv.typ.charCodeAt(y * data.cols + x) - 48;
    const p = partAt(lv, x, y);
    const bits = [`${x}, ${y}: ${(TERRAIN[t] || ["", "?"])[1]}`];
    bits.push(p ? (lv.parts.length > 1 ? `part ${p.n} (${p.id})` : `hand-built part (${p.id})`) + `, its square ${x - p.x}, ${y - p.y}`
      : "made by NetHack (different every game)");
    const st = lv.stairs.find((q) => q.x === x && q.y === y);
    if (st) bits.push((st.branch ? "branch " : "") + (st.ladder ? "ladder " : "stairs ") + (st.up ? "up" : "down"));
    if (lv.portals.some((q) => q.x === x && q.y === y)) bits.push("magic portal");
    if (show.regions) lv.regions.forEach((rg) => { if (regionHas(rg, x, y)) bits.push((REGIONS[rg.t] || { name: "region" }).name); });
    return bits.join(" · ");
  }

  function legend() {
    const sw = (col, text, cls = "") => `<span class="sl-key"><i class="${cls}" style="--c:${col}"></i>${esc(text)}</span>`;
    const terr = [[25, "floor"], [1, "wall"], [24, "corridor"], [23, "door"], [14, "secret door"],
      [16, "water"], [20, "lava"], [33, "ice"], [13, "tree"], [22, "iron bars"], [35, "air"], [36, "cloud"],
      [32, "altar"], [28, "fountain"], [29, "throne"], [0, "solid rock"]];
    return `
      <div class="sl-legend">
        <div>${terr.map(([t, n]) => sw(TERRAIN[t][0], n)).join("")}</div>
        <div>${sw("#b77ff0", "a hand-built part (outlined; numbered when there are several)", "ring")}
          ${sw("#8b8677", "made by NetHack around them - dimmed and hatched: different every game", "hatch")}</div>
        <div>${sw("#5bb0ff", "< up stairs", "dot")}${sw("#ff6b5b", "> down stairs", "dot")}${sw("#ffd23f", "branch stairs", "dot")}${sw("#d36bff", "◇ portal", "dot")}</div>
        <div>${Object.values(REGIONS).map((r) => sw(r.col, r.name, "dash")).join("")}</div>
      </div>`;
  }

  function card(lv) {
    const parts = lv.parts.map((p, i) => {
      const col = PART_COLORS[i % PART_COLORS.length];
      const built = !p.template ? "no area (not in the prefab editor)"
        : p.built === 0 ? "not built yet - the usual prefabs"
          : p.built >= p.squares ? "built" : `${p.built} of ${p.squares} squares built`;
      return `<li><span class="sl-swatch" style="--c:${col}"></span>
        <b>${lv.parts.length > 1 ? "Part " + p.n : "Hand-built part"}</b> <code>${esc(p.id)}</code>
        ${p.w}×${p.h} at ${p.x}, ${p.y} · ${esc(p.placed ? "placed " + p.placed : "placed where the level file puts it")}
        · <span class="${p.built ? "sl-ok" : "sl-dim"}">${esc(built)}</span></li>`;
    }).join("");
    const regs = [...new Set(lv.regions.map((r) => r.t))].map((t) => (REGIONS[t] || { name: "region " + t }).name);
    return `
      <article class="sl-card" data-proto="${esc(lv.proto)}">
        <header><h3>${esc(lv.name)}</h3><code>${esc(lv.proto)}.lua</code><span class="sl-group">${esc(lv.group)}</span></header>
        <ul class="sl-parts">${parts || "<li class='sl-dim'>No fixed parts: all of it is made by NetHack.</li>"}</ul>
        <p class="sl-meta"><b>Around ${lv.parts.length > 1 ? "them" : "it"}:</b> ${esc(lv.outside)}.
          <b>Flips:</b> ${esc(FLIPS[lv.allow] || "?")}${lv.allow ? " (the whole level, parts and all; the game turns your built squares to match)" : ""}.
          ${regs.length ? "<b>Regions:</b> " + esc(regs.join("; ")) + "." : ""}</p>
        <canvas class="sl-map"></canvas>
        <div class="sl-hover">Point at a square to see what it is.</div>
      </article>`;
  }

  function matches(lv) {
    const q = ($("#slSearch").value || "").trim().toLowerCase();
    const grp = $("#slGroup").value;
    if (grp && lv.group !== grp) return false;
    if ($("#slBuilt").checked && !lv.parts.some((p) => p.built)) return false;
    return !q || lv.name.toLowerCase().includes(q) || lv.proto.toLowerCase().includes(q);
  }

  function renderList() {
    const list = $("#slList");
    const shown = data.levels.filter(matches);
    list.innerHTML = shown.map(card).join("") || "<p class='hint'>No level matches.</p>";
    $("#slCount").textContent = `${shown.length} of ${data.levels.length} levels`;
    list.querySelectorAll(".sl-card").forEach((el) => {
      const lv = data.levels.find((l) => l.proto === el.dataset.proto);
      const cv = el.querySelector("canvas");
      draw(cv, lv);
      const hover = el.querySelector(".sl-hover");
      cv.addEventListener("mousemove", (e) => {
        const r = cv.getBoundingClientRect();
        const s = r.width / data.cols;
        hover.textContent = describe(lv, Math.floor((e.clientX - r.left) / s), Math.floor((e.clientY - r.top) / s));
      });
      cv.addEventListener("mouseleave", () => (hover.textContent = "Point at a square to see what it is."));
    });
  }

  async function render() {
    const body = $("#splevBody");
    if (!data) {
      body.innerHTML = "<p class='hint'>Loading…</p>";
      try { await load(); } catch (e) { body.innerHTML = `<p class="hint">Could not load the levels: ${esc(e.message)}</p>`; return; }
    }
    if (data.missing) {
      body.innerHTML = "<p class='hint'>No level data yet: run <code>python -I tools/make_splev_templates.py</code>.</p>";
      return;
    }
    if (rendered) return;
    rendered = true;
    const groups = [...new Set(data.levels.map((l) => l.group))];
    body.innerHTML = `
      <div class="sl-intro">
        <p>Every special level has parts that are always the same - drawn maps and fixed rooms in its level file. Those are the areas you build by hand in the prefab editor (<code>/area &lt;name&gt;</code>). Everything else on the level NetHack makes as it builds it, differently every game, and the game builds that from the usual prefabs, square by square. (A few bits inside the parts are random too - a small room that may or may not be there, a patch of swamp - so those squares can differ from game to game.)</p>
        <p>Each map below is one level as NetHack built it once, before any flip. NetHack tells the game where each part landed and which way the level was turned, and the game lays your squares out to match. A square you haven't built uses its usual prefab; so does any square whose terrain no longer matches (dug through, a door gone). Doors, stairs, ladders and drawbridges always use their own prefabs. (The Planes of Air and Water move around, so they have no fixed parts and aren't here.)</p>
      </div>
      <div class="toolbar">
        <input id="slSearch" type="search" placeholder="Search levels…">
        <select id="slGroup"><option value="">All of the dungeon</option>${groups.map((g) => `<option>${esc(g)}</option>`).join("")}</select>
        <label class="check"><input type="checkbox" id="slBuilt"> Only levels with built parts</label>
        <label class="check"><input type="checkbox" id="slShowOutside" checked> What NetHack makes</label>
        <label class="check"><input type="checkbox" id="slShowRegions" checked> Regions</label>
        <label class="check"><input type="checkbox" id="slShowStairs" checked> Stairs &amp; portals</label>
        <span class="count" id="slCount"></span>
      </div>
      ${legend()}
      <div id="slList"></div>`;
    $("#slSearch").addEventListener("input", renderList);
    $("#slGroup").addEventListener("change", renderList);
    $("#slBuilt").addEventListener("change", renderList);
    const toggle = (id, key) => $(id).addEventListener("change", (e) => { show[key] = e.target.checked; renderList(); });
    toggle("#slShowOutside", "outside");
    toggle("#slShowRegions", "regions");
    toggle("#slShowStairs", "stairs");
    let rt = null;
    window.addEventListener("resize", () => { clearTimeout(rt); rt = setTimeout(() => { if (!$("#tab-splev").hidden) renderList(); }, 200); });
    renderList();
  }

  return { render };
})();
