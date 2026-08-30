/* ph_inventory / html / app.js */
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

const S = {
    slots: 100, maxWeight: 450, weight: 0,
    items: {}, equipment: {}, hotbar: {},
    defs: {}, eqSlots: {}, eqOrder: [], hotN: 5, weapon: {}, nearby: [],
};

let drag = null;      // { kind:'grid'|'eq'|'hot'|'near', slot, eq, hot, nid, name, count }
let ctxSlot = null;
let countCtx = null;  // { op, slot, max }
let hoverTimer = null;

const def = (n) => S.defs[n] || {};
const badge = (n) => (def(n).label || n).replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase() || '??';

/* ---------------------------------------------------- cell builder */
function makeCell(opts) {
    // opts: { kind, slot?, eq?, hot?, nid?, item?, label?, keyNum? }
    const c = el('div', 'cell ' + (opts.kind === 'eq' ? 'eq ' : '') + (opts.item ? '' : 'empty'));
    if (opts.slot != null) c.dataset.slot = opts.slot;
    if (opts.eq != null) { c.dataset.eq = opts.eq; c.dataset.label = opts.label || opts.eq; }
    if (opts.hot != null) c.dataset.hot = opts.hot;
    if (opts.nid != null) c.dataset.nid = opts.nid;
    c.dataset.kind = opts.kind;

    if (opts.item) {
        const d = def(opts.item.name);
        const b = el('div', 'badge');
        b.textContent = badge(opts.item.name);
        c.appendChild(b);
        c.dataset.name = opts.item.name;
        c.dataset.count = opts.item.count || 1;

        if ((opts.item.count || 1) > 1) {
            const cnt = el('div', 'cnt'); cnt.textContent = opts.item.count; c.appendChild(cnt);
        }
        if (d.type === 'weapon' && opts.item.meta) {
            const max = S.weapon.MaxDurability || 100;
            const dura = el('div', 'dura');
            const i = el('i'); i.style.width = Math.max(0, Math.min(100, (opts.item.meta.durability / max) * 100)) + '%';
            dura.appendChild(i); c.appendChild(dura);
        }
    }
    if (opts.keyNum != null) {
        const k = el('div', 'key'); k.textContent = opts.keyNum; c.appendChild(k);
    }
    return c;
}

/* ---------------------------------------------------- render */
function renderEquipment() {
    const bottom = S.eqOrder.slice(-3);
    const rest = S.eqOrder.slice(0, -3);
    const half = Math.ceil(rest.length / 2);
    const groups = { 'eq-left': rest.slice(0, half), 'eq-right': rest.slice(half), 'eq-bottom': bottom };
    for (const [id, keys] of Object.entries(groups)) {
        const host = document.getElementById(id);
        host.innerHTML = '';
        keys.forEach((k) => {
            const worn = S.equipment[k];
            host.appendChild(makeCell({
                kind: 'eq', eq: k, label: (S.eqSlots[k] && S.eqSlots[k].label) || k,
                item: worn ? { name: worn.name, count: 1, meta: worn.meta } : null,
            }));
        });
    }
}

function renderHotbar() {
    const host = $('#hotbar');
    host.innerHTML = '';
    for (let i = 1; i <= S.hotN; i++) {
        const slot = S.hotbar[i];
        const item = slot != null ? S.items[slot] : null;
        host.appendChild(makeCell({ kind: 'hot', hot: i, item, keyNum: i }));
    }
}

function renderGrid() {
    const host = $('#grid');
    host.innerHTML = '';
    const q = $('#search').value.trim().toLowerCase();
    for (let i = 1; i <= S.slots; i++) {
        const item = S.items[i];
        const c = makeCell({ kind: 'grid', slot: i, item });
        if (q && item && !(def(item.name).label || item.name).toLowerCase().includes(q)) c.classList.add('dim');
        host.appendChild(c);
    }
}

function renderNearby() {
    const host = $('#nearby');
    host.innerHTML = '';
    (S.nearby || []).forEach((drop) => {
        (drop.items || []).forEach((it) => {
            host.appendChild(makeCell({
                kind: 'near', nid: drop.id,
                item: { name: it.name, count: it.count },
            }));
        });
    });
}

function renderWeight() {
    $('#weight').textContent = `${Math.round(S.weight)}/${Math.round(S.maxWeight)}`;
    $('#weight-bar i').style.width = Math.min(100, (S.weight / S.maxWeight) * 100) + '%';
}

function renderAll() { renderEquipment(); renderHotbar(); renderGrid(); renderWeight(); }

/* ---------------------------------------------------- drag & drop */
function cellInfo(c) {
    if (!c) return null;
    const k = c.dataset.kind;
    return {
        kind: k, node: c,
        slot: c.dataset.slot != null ? +c.dataset.slot : undefined,
        eq: c.dataset.eq,
        hot: c.dataset.hot != null ? +c.dataset.hot : undefined,
        nid: c.dataset.nid != null ? +c.dataset.nid : undefined,
        name: c.dataset.name,
        count: c.dataset.count != null ? +c.dataset.count : 1,
    };
}

document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    const c = e.target.closest('.cell');
    if (!c || c.classList.contains('empty') || !c.dataset.name) return;
    drag = cellInfo(c);
    const g = $('#ghost');
    g.textContent = badge(drag.name);
    g.classList.remove('hidden');
    moveGhost(e);
    e.preventDefault();
});

function moveGhost(e) {
    const g = $('#ghost');
    g.style.left = e.clientX - 26 + 'px';
    g.style.top = e.clientY - 26 + 'px';
}

document.addEventListener('mousemove', (e) => {
    if (!drag) return;
    moveGhost(e);
    const dz = $('#dropzone');
    const overDz = document.elementFromPoint(e.clientX, e.clientY)?.closest('#dropzone');
    dz.classList.toggle('over', !!overDz);
});

document.addEventListener('mouseup', (e) => {
    if (!drag) return;
    const src = drag;
    drag = null;
    $('#ghost').classList.add('hidden');
    $('#dropzone').classList.remove('over');

    const under = document.elementFromPoint(e.clientX, e.clientY);
    if (!under) return;

    if (under.closest('#dropzone')) {
        if (src.kind === 'grid') post('context', { op: 'drop', slot: src.slot, count: src.count });
        else if (src.kind === 'hot') post('setHotbar', { hotIndex: src.hot, slot: null });
        return;
    }

    const tc = under.closest('.cell');
    if (!tc) {
        if (src.kind === 'hot') post('setHotbar', { hotIndex: src.hot, slot: null });
        return;
    }
    const t = cellInfo(tc);

    if (src.kind === 'grid') {
        if (t.kind === 'grid') {
            const ti = S.items[t.slot];
            if (ti && def(ti.name).type === 'weapon' && def(src.name).type === 'ammo') {
                post('loadAmmo', { ammoSlot: src.slot, weaponSlot: t.slot });
            } else {
                post('move', { from: src.slot, to: t.slot, count: src.count });
            }
        } else if (t.kind === 'eq') {
            post('equip', { slot: src.slot });
        } else if (t.kind === 'hot') {
            post('setHotbar', { hotIndex: t.hot, slot: src.slot });
        }
    } else if (src.kind === 'eq') {
        if (t.kind === 'grid') post('unequip', { eqSlot: src.eq });
    } else if (src.kind === 'hot') {
        if (t.kind === 'grid') post('setHotbar', { hotIndex: src.hot, slot: null });
    } else if (src.kind === 'near') {
        post('pickup', { id: src.nid });
    }
});

/* ---------------------------------------------------- context menu */
document.addEventListener('contextmenu', (e) => {
    const c = e.target.closest('#grid .cell');
    if (!c || c.classList.contains('empty')) { hideCtx(); return; }
    e.preventDefault();
    ctxSlot = +c.dataset.slot;
    const it = S.items[ctxSlot];
    const d = def(it.name);
    $('#ctx').querySelector('[data-op="use"]').style.display = d.usable ? '' : 'none';
    $('#ctx').querySelector('[data-op="split"]').style.display = (it.count > 1 && !it.meta) ? '' : 'none';
    const ctx = $('#ctx');
    ctx.style.left = Math.min(e.clientX, window.innerWidth - 140) + 'px';
    ctx.style.top = Math.min(e.clientY, window.innerHeight - 120) + 'px';
    ctx.classList.remove('hidden');
});

function hideCtx() { $('#ctx').classList.add('hidden'); ctxSlot = null; }

$('#ctx').addEventListener('click', (e) => {
    const op = e.target.dataset.op;
    if (!op || ctxSlot == null) return;
    const it = S.items[ctxSlot];
    if (op === 'use') {
        post('context', { op: 'use', slot: ctxSlot });
    } else if (op === 'split') {
        openCount('split', ctxSlot, it.count - 1);
    } else if (op === 'drop') {
        openCount('drop', ctxSlot, it.count);
    }
    hideCtx();
});

document.addEventListener('click', (e) => {
    if (!e.target.closest('#ctx')) hideCtx();
});

/* ---------------------------------------------------- count box */
function openCount(op, slot, max) {
    countCtx = { op, slot, max };
    const inp = $('#count-input');
    inp.max = max; inp.value = Math.min(1, max) || 1; inp.value = 1;
    $('#countbox').classList.remove('hidden');
    inp.focus();
}
$('#cb-cancel').onclick = () => { $('#countbox').classList.add('hidden'); countCtx = null; };
$('#cb-ok').onclick = () => {
    if (!countCtx) return;
    let n = parseInt($('#count-input').value, 10) || 1;
    n = Math.max(1, Math.min(n, countCtx.max));
    post('context', { op: countCtx.op, slot: countCtx.slot, count: n });
    $('#countbox').classList.add('hidden');
    countCtx = null;
};

/* ---------------------------------------------------- weapon tooltip */
document.addEventListener('mouseover', (e) => {
    const c = e.target.closest('#grid .cell, #hotbar .cell');
    if (!c || !c.dataset.name) return;
    const it = c.dataset.hot != null ? S.items[S.hotbar[+c.dataset.hot]] : S.items[+c.dataset.slot];
    if (!it || !it.meta || def(it.name).type !== 'weapon') return;
    clearTimeout(hoverTimer);
    hoverTimer = setTimeout(() => {
        const tip = $('#tip');
        tip.innerHTML =
            `<b>${def(it.name).label}</b><br>Gloante: ${it.meta.ammo || 0}/${S.weapon.MaxLoadedAmmo || 500}` +
            `<br>Durabilitate: ${Math.round(it.meta.durability || 0)}%`;
        const r = c.getBoundingClientRect();
        tip.style.left = Math.min(r.right + 8, window.innerWidth - 180) + 'px';
        tip.style.top = r.top + 'px';
        tip.classList.remove('hidden');
    }, S.weapon.HoverTooltipMs || 2000);
});
document.addEventListener('mouseout', (e) => {
    if (e.target.closest('.cell')) { clearTimeout(hoverTimer); $('#tip').classList.add('hidden'); }
});

/* ---------------------------------------------------- misc */
$('#search').addEventListener('input', renderGrid);

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (!$('#countbox').classList.contains('hidden')) { $('#countbox').classList.add('hidden'); countCtx = null; return; }
        if (!$('#ctx').classList.contains('hidden')) { hideCtx(); return; }
        post('close');
    }
});

/* ---------------------------------------------------- messages */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        $('#inv').classList.remove('hidden');
    } else if (d.action === 'close') {
        $('#inv').classList.add('hidden');
        hideCtx();
        $('#countbox').classList.add('hidden');
        $('#tip').classList.add('hidden');
        drag = null; $('#ghost').classList.add('hidden');
    } else if (d.action === 'state') {
        Object.assign(S, d.data || {});
        S.items = {}; S.hotbar = {};
        for (const [k, v] of Object.entries((d.data && d.data.items) || {})) S.items[+k] = v;
        for (const [k, v] of Object.entries((d.data && d.data.hotbar) || {})) S.hotbar[+k] = +v;
        S.eqSlots = (d.data && d.data.equipmentSlots) || S.eqSlots;
        S.eqOrder = (d.data && d.data.equipmentOrder) || S.eqOrder;
        S.hotN = (d.data && d.data.hotbarSlots) || S.hotN;
        S.weapon = (d.data && d.data.weapon) || S.weapon;
        renderAll();
    } else if (d.action === 'nearby') {
        S.nearby = d.data || [];
        renderNearby();
    }
});
