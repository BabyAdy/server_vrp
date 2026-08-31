/* ph_inventory / html / app.js
 * ----------------------------------------------------------------------------
 *  SERVER-DRIVEN.  Regula de aur:
 *    - drag & drop / click NU modifica niciodata `S.items` / `S.hotbar` / DOM-ul
 *      de date.  Fiecare actiune trimite un `post(...)` catre client.lua -> server.
 *    - serverul raspunde cu `state` -> abia atunci `paintAll()` redeseneaza.
 *  Sloturile sunt STRICT numere intregi (parseInt), aceleasi ca in Lua:
 *    grid 1..slots, haine 5001..5011, fast slots 6001..6000+hotN.
 *  Fast slot-urile TIN itemul (nu mai e pointer) -> un item de pe hotbar NU
 *  mai apare si in grid.
 * ----------------------------------------------------------------------------
 */
const RES = 'ph_inventory';
function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}
const $ = (s) => document.querySelector(s);
const el = (t, c) => { const e = document.createElement(t); if (c) e.className = c; return e; };

/** parse strict la int; null daca nu e numar finit */
const toInt = (v) => {
    if (v === null || v === undefined || v === '') return null;
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : null;
};

/* ---------------------------------------------------- state (oglinda serverului) */
const S = {
    slots: 100, maxWeight: 450, weight: 0,
    items: {}, equipment: {}, hotbar: {},
    defs: {}, eqSlots: {}, eqOrder: [], eqSlotIds: {}, clothingSlots: {},
    hotN: 5, hotbarBase: 6001, weapon: {}, attachments: {}, nearby: [],
};
let configReady = false;
let drag = null;                 // { kind, slot, hot, nid, name, count, node }
let ctxSlot = null;
let countCtx = null;
let hoverTimer = null;

const gridCells = [];            // index 1..slots -> refs
const hotCells = [];             // index 1..hotN  -> refs
let eqBuilt = false;

const def = (n) => S.defs[n] || {};
const short = (n) => (def(n).label || n).replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase() || '??';
const iconSrc = (n) => `img/${def(n).image || n}.png`;

/** un slot fast? */
const isHotSlot = (slot) => slot != null && slot >= S.hotbarBase && slot < S.hotbarBase + S.hotN;
/** intrarea din state pentru orice slot real (grid sau fast) */
const slotEntry = (slot) => {
    if (slot == null) return null;
    if (isHotSlot(slot)) return S.hotbar[slot - S.hotbarBase + 1] || null;
    return S.items[slot] || null;
};

/* ---------------------------------------------------- cell paint (in place) */
function paintCell(refs, item) {
    if (!refs) return;
    const durTxt = (item && item.meta && item.meta.durability != null)
        ? Math.round(item.meta.durability) + ':' + (item.meta.ammo || 0)
          + ':' + ((item.meta.attachments || []).join(',')) : '';
    const sig = item ? `${item.name}|${item.count || 1}|${durTxt}` : '';
    if (refs._sig === sig) return;
    refs._sig = sig;

    const { node } = refs;
    node.classList.toggle('empty', !item);
    if (!item) {
        node.removeAttribute('data-name');
        node.removeAttribute('data-count');
        refs.badge.style.display = 'none';
        refs.img.style.display = 'none';
        refs.cnt.style.display = 'none';
        refs.dura.style.display = 'none';
        return;
    }

    node.dataset.name = item.name;
    node.dataset.count = item.count || 1;

    const d = def(item.name);
    refs.img.style.display = '';
    refs.badge.style.display = 'none';
    if (refs.img.getAttribute('src') !== iconSrc(item.name)) {
        refs.img.setAttribute('src', iconSrc(item.name));
    }
    refs.img.onerror = () => {
        refs.img.style.display = 'none';
        refs.badge.style.display = '';
        refs.badge.textContent = short(item.name);
    };

    if ((item.count || 1) > 1) { refs.cnt.style.display = ''; refs.cnt.textContent = item.count; }
    else refs.cnt.style.display = 'none';

    if (d.type === 'weapon' && item.meta && item.meta.durability != null) {
        const max = d.maxDurability || S.weapon.MaxDurability || 100;
        refs.dura.style.display = '';
        refs.dura.firstChild.style.width = Math.max(0, Math.min(100, (item.meta.durability / max) * 100)) + '%';
        refs.node.classList.toggle('has-mods', !!(item.meta.attachments && item.meta.attachments.length));
    } else {
        refs.dura.style.display = 'none';
        refs.node.classList.remove('has-mods');
    }
}

function makeCellNode(kind, extra) {
    const node = el('div', 'cell empty' + (kind === 'eq' ? ' eq' : ''));
    node.dataset.kind = kind;
    Object.assign(node.dataset, extra || {});
    const img = el('img'); img.className = 'ic'; img.style.display = 'none'; img.draggable = false;
    const badge = el('div', 'badge'); badge.style.display = 'none';
    const cnt = el('div', 'cnt'); cnt.style.display = 'none';
    const dura = el('div', 'dura'); dura.appendChild(el('i')); dura.style.display = 'none';
    node.append(img, badge, cnt, dura);
    return { node, img, badge, cnt, dura, _sig: ' ' };
}

/* ---------------------------------------------------- build once */
function buildGrid() {
    const host = $('#grid');
    host.innerHTML = '';
    gridCells.length = 0;
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= S.slots; i++) {
        const refs = makeCellNode('grid', { slot: String(i) });
        gridCells[i] = refs;
        frag.appendChild(refs.node);
    }
    host.appendChild(frag);
}

function buildHotbar() {
    const host = $('#hotbar');
    host.innerHTML = '';
    hotCells.length = 0;
    for (let i = 1; i <= S.hotN; i++) {
        const refs = makeCellNode('hot', { hot: String(i), slot: String(S.hotbarBase + i - 1) });
        const k = el('div', 'key'); k.textContent = i; refs.node.appendChild(k);
        hotCells[i] = refs;
        host.appendChild(refs.node);
    }
}

function buildEquipment() {
    S.eqRefs = {};
    const ids = S.eqSlotIds || {};
    const bottom = S.eqOrder.slice(-3);
    const rest = S.eqOrder.slice(0, -3);
    const half = Math.ceil(rest.length / 2);
    const groups = { 'eq-left': rest.slice(0, half), 'eq-right': rest.slice(half), 'eq-bottom': bottom };
    for (const [id, keys] of Object.entries(groups)) {
        const h = document.getElementById(id);
        h.innerHTML = '';
        keys.forEach((k) => {
            const num = toInt(ids[k]);
            const label = (S.eqSlots[k] && S.eqSlots[k].label) || k;
            const refs = makeCellNode('eq', { eq: k, slot: num != null ? String(num) : '', label });
            refs.node.dataset.label = label;
            refs.node._eqKey = k;
            h.appendChild(refs.node);
            S.eqRefs[k] = refs;
        });
    }
    eqBuilt = true;
}

/* ---------------------------------------------------- paint dynamic */
function paintAll() {
    for (let i = 1; i <= S.slots; i++) paintCell(gridCells[i], S.items[i] || null);
    for (let i = 1; i <= S.hotN; i++) paintCell(hotCells[i], S.hotbar[i] || null);
    if (eqBuilt) for (const k of S.eqOrder) {
        const worn = S.equipment[k];
        paintCell(S.eqRefs[k], worn ? { name: worn.name, count: 1, meta: worn.meta } : null);
    }
    $('#weight').textContent = `${Math.round(S.weight)}/${Math.round(S.maxWeight)}`;
    $('#weight-bar i').style.width = Math.min(100, (S.weight / S.maxWeight) * 100) + '%';
    applySearch();
}

function applySearch() {
    const q = $('#search').value.trim().toLowerCase();
    for (let i = 1; i <= S.slots; i++) {
        const it = S.items[i];
        gridCells[i].node.classList.toggle('dim',
            !!q && !!it && !(def(it.name).label || it.name).toLowerCase().includes(q));
    }
}

function renderNearby() {
    const host = $('#nearby');
    host.innerHTML = '';
    const frag = document.createDocumentFragment();
    (S.nearby || []).forEach((drop) => (drop.items || []).forEach((it) => {
        const refs = makeCellNode('near', { nid: String(drop.id) });
        frag.appendChild(refs.node);
        paintCell(refs, { name: it.name, count: it.count });
    }));
    host.appendChild(frag);
}

/* ---------------------------------------------------- drag & drop */
function cellInfo(c) {
    if (!c) return null;
    return {
        kind: c.dataset.kind,
        node: c,
        slot: toInt(c.dataset.slot),
        hot: toInt(c.dataset.hot),
        nid: toInt(c.dataset.nid),
        name: c.dataset.name || null,
        count: toInt(c.dataset.count) || 1,
    };
}

let ghostX = 0, ghostY = 0, ghostRAF = 0;
function ghostLoop() {
    ghostRAF = 0;
    $('#ghost').style.transform = `translate3d(${ghostX - 26}px, ${ghostY - 26}px, 0)`;
}
function queueGhost() { if (!ghostRAF) ghostRAF = requestAnimationFrame(ghostLoop); }

document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    const c = e.target.closest('.cell');
    if (!c || c.classList.contains('empty') || !c.dataset.name) return;
    drag = cellInfo(c);
    const g = $('#ghost');
    const img = iconSrc(drag.name);
    g.innerHTML = `<img src="${img}" onerror="this.replaceWith(document.createTextNode('${short(drag.name)}'))">`;
    ghostX = e.clientX; ghostY = e.clientY;
    g.classList.remove('hidden');
    queueGhost();
    e.preventDefault();
});

document.addEventListener('mousemove', (e) => {
    if (!drag) return;
    ghostX = e.clientX; ghostY = e.clientY;
    queueGhost();
});

let dzOverRAF = 0;
document.addEventListener('mousemove', () => {
    if (!drag || dzOverRAF) return;
    dzOverRAF = requestAnimationFrame(() => {
        dzOverRAF = 0;
        const over = document.elementFromPoint(ghostX, ghostY);
        $('#dropzone').classList.toggle('over', !!(over && over.closest('#dropzone')));
    });
});

document.addEventListener('mouseup', (e) => {
    if (!drag) return;
    const src = drag;
    drag = null;
    $('#ghost').classList.add('hidden');
    $('#dropzone').classList.remove('over');

    const under = document.elementFromPoint(e.clientX, e.clientY);
    if (!under) return;

    /* ---- DROPZONE: arunca pe jos ---- */
    if (under.closest('#dropzone')) {
        if ((src.kind === 'grid' || src.kind === 'hot') && src.slot != null) {
            post('context', { op: 'drop', slot: src.slot, count: src.count });
        }
        return;
    }

    const tc = under.closest('.cell');
    if (!tc) return;
    const t = cellInfo(tc);

    /* ---- sursa: NEARBY (ridica de pe jos) ---- */
    if (src.kind === 'near') {
        if (src.nid != null) post('pickup', { id: src.nid });
        return;
    }

    /* ---- restul: totul e un `move` numeric intre doua sloturi ---- */
    if (src.slot == null || t.slot == null || src.slot === t.slot) return;

    // ammo / atasament -> arma (doar cand tinta e o arma)
    const tEnt = slotEntry(t.slot);
    if (tEnt && def(tEnt.name).type === 'weapon') {
        const sd = def(src.name);
        if (sd.type === 'ammo') {
            post('loadAmmo', { ammoSlot: src.slot, weaponSlot: t.slot });
            return;
        }
        if (sd.type === 'attachment') {
            post('applyAttachment', { attachSlot: src.slot, weaponSlot: t.slot });
            return;
        }
    }

    post('move', { from: src.slot, to: t.slot, count: src.count });
});

/* ---------------------------------------------------- context menu */
function openCtx(e, slot) {
    const it = slotEntry(slot);
    if (!it) return;
    ctxSlot = slot;
    const d = def(it.name);
    const ctx = $('#ctx');

    ctx.querySelector('[data-op="use"]').style.display = d.usable ? '' : 'none';
    ctx.querySelector('[data-op="split"]').style.display =
        (!isHotSlot(slot) && it.count > 1 && !it.meta) ? '' : 'none';

    // butoane ✕ pentru fiecare atasament montat
    ctx.querySelectorAll('.attach-btn').forEach((b) => b.remove());
    if (d.type === 'weapon' && it.meta && (it.meta.attachments || []).length) {
        it.meta.attachments.forEach((key) => {
            const b = el('button', 'attach-btn');
            const label = (S.attachments[key] && S.attachments[key].label) || key;
            b.textContent = `✕ ${label}`;
            b.dataset.attach = key;
            ctx.appendChild(b);
        });
    }

    ctx.style.left = Math.min(e.clientX, innerWidth - 160) + 'px';
    ctx.style.top = Math.min(e.clientY, innerHeight - 160) + 'px';
    ctx.classList.remove('hidden');
}
function ctxHandler(e) {
    const c = e.target.closest('.cell');
    if (!c || c.classList.contains('empty')) return;
    e.preventDefault();
    openCtx(e, toInt(c.dataset.slot));
}
$('#grid').addEventListener('contextmenu', ctxHandler);
$('#hotbar').addEventListener('contextmenu', ctxHandler);
function hideCtx() {
    const ctx = $('#ctx');
    ctx.classList.add('hidden');
    ctx.querySelectorAll('.attach-btn').forEach((b) => b.remove());
    ctxSlot = null;
}
$('#ctx').addEventListener('click', (e) => {
    if (ctxSlot == null) return;
    const btn = e.target.closest('button');
    if (!btn) return;
    const it = slotEntry(ctxSlot);
    if (!it) { hideCtx(); return; }

    if (btn.dataset.attach) {
        post('context', { op: 'rmattach', slot: ctxSlot, attach: btn.dataset.attach });
        hideCtx();
        return;
    }
    const op = btn.dataset.op;
    if (op === 'use') post('context', { op: 'use', slot: ctxSlot });
    else if (op === 'split') openCount('split', ctxSlot, it.count - 1);
    else if (op === 'drop') openCount('drop', ctxSlot, it.count);
    hideCtx();
});
document.addEventListener('mousedown', (e) => { if (!e.target.closest('#ctx')) hideCtx(); }, true);

/* ---------------------------------------------------- count box */
function openCount(op, slot, max) {
    countCtx = { op, slot: toInt(slot), max };
    const inp = $('#count-input');
    inp.max = max; inp.value = Math.min(1, max) || 1;
    $('#countbox').classList.remove('hidden');
    inp.focus(); inp.select();
}
$('#cb-cancel').onclick = () => { $('#countbox').classList.add('hidden'); countCtx = null; };
$('#cb-ok').onclick = () => {
    if (!countCtx) return;
    const n = Math.max(1, Math.min(parseInt($('#count-input').value, 10) || 1, countCtx.max));
    post('context', { op: countCtx.op, slot: countCtx.slot, count: n });
    $('#countbox').classList.add('hidden'); countCtx = null;
};

/* ---------------------------------------------------- weapon tooltip */
function tipTarget(c) {
    if (!c || !c.dataset.name) return null;
    const it = slotEntry(toInt(c.dataset.slot));
    return (it && it.meta && def(it.name).type === 'weapon') ? { it, c } : null;
}
$('#grid').addEventListener('mouseover', onHover);
$('#hotbar').addEventListener('mouseover', onHover);
function onHover(e) {
    const tgt = tipTarget(e.target.closest('.cell'));
    if (!tgt) return;
    clearTimeout(hoverTimer);
    hoverTimer = setTimeout(() => {
        const d = def(tgt.it.name);
        const m = tgt.it.meta;
        const maxA = d.maxAmmo || S.weapon.MaxLoadedAmmo || 500;
        const maxD = Math.round(d.maxDurability || S.weapon.MaxDurability || 100);
        const att = (m.attachments || []).map((k) => (S.attachments[k] && S.attachments[k].label) || k);
        const tip = $('#tip');
        tip.innerHTML =
            `<b>${d.label || tgt.it.name}</b>` +
            `<br>Ammo: ${m.ammo || 0}/${maxA}` +
            `<br>Durability: ${Math.round(m.durability || 0)}/${maxD}` +
            `<br>Atasamente: ${att.length ? att.join(', ') : '—'}` +
            (att.length ? `<br><span class="tip-sub">(one time use — scoase din meniul ✕)</span>` : '');
        const r = tgt.c.getBoundingClientRect();
        tip.style.left = Math.min(r.right + 8, innerWidth - 230) + 'px';
        tip.style.top = Math.max(6, r.top) + 'px';
        tip.classList.remove('hidden');
    }, S.weapon.HoverTooltipMs || 2000);
}
document.addEventListener('mouseout', (e) => {
    if (e.target.closest('.cell')) { clearTimeout(hoverTimer); $('#tip').classList.add('hidden'); }
});

/* ---------------------------------------------------- misc */
$('#search').addEventListener('input', applySearch);
document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('#countbox').classList.contains('hidden')) { $('#countbox').classList.add('hidden'); countCtx = null; return; }
    if (!$('#ctx').classList.contains('hidden')) { hideCtx(); return; }
    post('close');
});

/* ---------------------------------------------------- ingest state de la server */
function ingestItems(raw) {
    const out = {};
    if (Array.isArray(raw)) {
        raw.forEach((e) => {
            if (!e) return;
            const sl = toInt(e.slot);
            if (sl != null) out[sl] = { name: e.name, count: e.count, meta: e.meta };
        });
    } else if (raw && typeof raw === 'object') {
        for (const [k, v] of Object.entries(raw)) {
            const sl = toInt(k);
            if (sl != null && v) out[sl] = { name: v.name, count: v.count, meta: v.meta };
        }
    }
    return out;
}

function ingestHotbar(raw) {
    // serverul trimite mereu lista { {i, name, count, meta}, ... }
    const out = {};
    const list = Array.isArray(raw) ? raw : (raw && typeof raw === 'object' ? Object.values(raw) : []);
    list.forEach((v) => {
        if (!v || typeof v !== 'object' || v.name == null) return;
        const i = toInt(v.i);
        if (i != null) out[i] = { name: v.name, count: v.count, meta: v.meta };
    });
    return out;
}

/* ---------------------------------------------------- messages */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        $('#inv').classList.remove('hidden');
    } else if (d.action === 'close') {
        $('#inv').classList.add('hidden');
        hideCtx(); $('#countbox').classList.add('hidden'); $('#tip').classList.add('hidden');
        drag = null; $('#ghost').classList.add('hidden');
    } else if (d.action === 'config') {
        const c = d.data || {};
        S.defs = c.defs || {};
        S.eqSlots = c.equipmentSlots || {};
        S.eqOrder = c.equipmentOrder || [];
        S.eqSlotIds = c.equipmentSlotIds || {};
        S.clothingSlots = c.clothingSlots || {};
        S.hotN = c.hotbarSlots || 5;
        S.hotbarBase = c.hotbarBase || 6001;
        S.weapon = c.weapon || {};
        S.attachments = c.attachments || {};
        S.maxWeight = c.maxWeight || 450;
        S.slots = c.slots || 100;
        buildGrid(); buildHotbar(); buildEquipment();
        configReady = true;
        paintAll();
    } else if (d.action === 'state') {
        const s = d.data || {};
        if (s.slots && s.slots !== S.slots) { S.slots = s.slots; if (configReady) buildGrid(); }
        S.items = ingestItems(s.items);
        S.hotbar = ingestHotbar(s.hotbar);
        S.equipment = (s.equipment && typeof s.equipment === 'object' && !Array.isArray(s.equipment)) ? s.equipment : {};
        S.weight = s.weight || 0;
        if (configReady) paintAll();
    } else if (d.action === 'nearby') {
        S.nearby = d.data || [];
        renderNearby();
    }
});
