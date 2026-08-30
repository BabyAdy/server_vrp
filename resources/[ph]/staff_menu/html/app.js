/* staff_menu / html / app.js */
const RES = 'staff_menu';

function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));
}

const $ = (id) => document.getElementById(id);
const esc = (s) =>
    String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const TABS = [
    { id: 'staff', label: 'Staff' },
    { id: 'tickets', label: 'Tickets' },
    { id: 'active', label: 'Active Tickets' },
    { id: 'players', label: 'Players' },
    { id: 'developer', label: 'Developer' },
];

const STATE = {
    perms: {}, grades: {}, categories: [], staffActions: [],
    selected: null, tab: null, players: [], modalAction: null,
};

/* ------------------------------------------------ build */
function buildMenu(d) {
    STATE.perms = d.perms || {};
    STATE.grades = d.grades || {};
    STATE.categories = d.categories || [];
    STATE.staffActions = d.staffActions || [];
    STATE.selected = null;

    $('me-name').textContent = (d.me && d.me.name) || '-';
    $('me-rank').textContent = (d.me && d.me.staff) || 'staff';

    // grade select (developer)
    const gsel = $('dev-staff-grade');
    gsel.innerHTML = '<option value="">— fara staff —</option>' +
        Object.keys(STATE.grades).map((k) => `<option value="${k}">${esc(STATE.grades[k].label)}</option>`).join('');

    // tabs
    const nav = $('tabs');
    nav.innerHTML = '';
    TABS.forEach((t) => {
        if (!STATE.perms['tab_' + t.id]) return;
        const b = document.createElement('button');
        b.textContent = t.label;
        b.dataset.tab = t.id;
        b.onclick = () => showTab(t.id);
        nav.appendChild(b);
    });

    buildStaffActions();
    updateTargetBar();

    const first = TABS.find((t) => STATE.perms['tab_' + t.id]);
    if (first) showTab(first.id);
}

function buildStaffActions() {
    const grid = $('staff-actions');
    grid.innerHTML = '';
    STATE.staffActions.forEach((a) => {
        if (!STATE.perms[a.id]) return;
        const b = document.createElement('button');
        b.textContent = a.label;
        b.dataset.action = a.id;
        b.onclick = () => onAction(a);
        grid.appendChild(b);
    });
    refreshActionState();
}

function refreshActionState() {
    document.querySelectorAll('#staff-actions button').forEach((b) => {
        const a = STATE.staffActions.find((x) => x.id === b.dataset.action);
        b.disabled = !!(a && a.needsTarget && !STATE.selected);
    });
}

function updateTargetBar() {
    $('target-label').textContent = STATE.selected
        ? `${STATE.selected.name} (#${STATE.selected.id})`
        : 'niciun jucator selectat';
}

/* ------------------------------------------------ tabs */
function showTab(id) {
    STATE.tab = id;
    document.querySelectorAll('#tabs button').forEach((b) => b.classList.toggle('active', b.dataset.tab === id));
    document.querySelectorAll('.tab').forEach((s) => s.classList.toggle('active', s.dataset.tab === id));

    if (id === 'players') post('players');
    else if (id === 'tickets') post('ticket', { op: 'list' });
    else if (id === 'active') post('ticket', { op: 'listActive' });
    else if (id === 'developer') post('dev', { op: 'server_info' });
}

/* ------------------------------------------------ renderers */
function fmtTime(s) { return s ? String(s).replace('T', ' ').slice(0, 16) : ''; }

function renderPlayers(list) {
    STATE.players = list || [];
    filterPlayers();
}

function filterPlayers() {
    const q = $('player-search').value.trim().toLowerCase();
    const rows = STATE.players.filter((p) =>
        !q || String(p.id).includes(q) || (p.name || '').toLowerCase().includes(q));

    $('players-list').innerHTML = rows.map((p) => `
        <div class="card">
          <div class="top">
            <span class="id">#${esc(p.id)}</span>
            <span class="name">${esc(p.name)}</span>
            ${p.staffLabel ? `<span class="tag" style="color:${esc(p.staffColor || '#b98cff')}">${esc(p.staffLabel)}</span>` : ''}
            <span class="meta">src ${esc(p.src)} · ${esc(p.ping)}ms</span>
          </div>
          <div class="acts">
            <button class="mini go" data-sel="${p.src}">Select</button>
          </div>
        </div>`).join('') || '<div class="card">Niciun jucator.</div>';

    $('players-list').querySelectorAll('[data-sel]').forEach((b) => {
        b.onclick = () => {
            const p = STATE.players.find((x) => String(x.src) === b.dataset.sel);
            if (!p) return;
            STATE.selected = p;
            updateTargetBar();
            refreshActionState();
            if (STATE.perms.tab_staff) showTab('staff');
        };
    });
}

function ticketCard(t, active) {
    return `<div class="card">
      <div class="top">
        <span class="id">#${esc(t.id)}</span>
        <span class="tag">${esc(t.category)}</span>
        <span class="name">${esc(t.username)}</span>
        <span class="tag">uid ${esc(t.user_id)}</span>
        <span class="meta">${esc(fmtTime(t.created_at))}</span>
      </div>
      <div class="msg">${esc(t.message)}</div>
      <div class="acts">
        ${active
            ? `<button class="mini" data-t="goto" data-id="${t.id}">Goto</button>
               <button class="mini" data-t="reply" data-id="${t.id}">Reply</button>
               <button class="mini go" data-t="close" data-id="${t.id}">Close</button>`
            : `<button class="mini go" data-t="accept" data-id="${t.id}">Accept</button>
               <button class="mini" data-t="close" data-id="${t.id}">Close</button>`}
      </div>
    </div>`;
}

function wireTicketButtons(container) {
    container.querySelectorAll('[data-t]').forEach((b) => {
        b.onclick = () => {
            const op = b.dataset.t, id = Number(b.dataset.id);
            if (op === 'reply') {
                STATE.modalAction = { kind: 'ticketReply', id };
                openModal('Raspuns tichet #' + id, { text: true });
            } else {
                post('ticket', { op, id });
            }
        };
    });
}

function renderTickets(list) {
    const c = $('tickets-list');
    c.innerHTML = (list && list.length) ? list.map((t) => ticketCard(t, false)).join('') : '<div class="card">Niciun tichet deschis.</div>';
    wireTicketButtons(c);
}

function renderActive(list) {
    const c = $('active-list');
    c.innerHTML = (list && list.length) ? list.map((t) => ticketCard(t, true)).join('') : '<div class="card">Niciun tichet activ.</div>';
    wireTicketButtons(c);
}

function renderDevInfo(info) {
    if (!info) return;
    const up = info.uptime || 0;
    const h = Math.floor(up / 3600), m = Math.floor((up % 3600) / 60);
    $('dev-info').innerHTML =
        `Uptime: ${h}h ${m}m<br>Jucatori: ${info.players} / ${info.maxPlayers}<br>Resurse: ${info.resources}`;
}

/* ------------------------------------------------ actions */
function onAction(a) {
    if (a.needsTarget && !STATE.selected) return toast('Selecteaza un jucator.');

    const need = {};
    if (a.needsReason) need.reason = true;
    if (a.needsDays) need.days = true;
    if (a.needsText) need.text = true;
    if (a.needsRef) need.ref = true;

    if (Object.keys(need).length) {
        STATE.modalAction = { kind: 'action', action: a.id };
        openModal(a.label, need);
    } else {
        sendAction(a.id, {});
    }
}

function sendAction(action, extra) {
    const payload = { action, ...extra };
    if (STATE.selected) payload.targetSrc = STATE.selected.src;
    post('action', payload);
}

/* ------------------------------------------------ modal */
function openModal(title, fields) {
    $('modal-title').textContent = title;
    $('m-reason-w').classList.toggle('hidden', !fields.reason);
    $('m-days-w').classList.toggle('hidden', !fields.days);
    $('m-text-w').classList.toggle('hidden', !fields.text);
    $('m-ref-w').classList.toggle('hidden', !fields.ref);
    $('m-reason').value = '';
    $('m-days').value = '0';
    $('m-text').value = '';
    $('m-ref').value = '';
    $('modal').classList.remove('hidden');
}

function closeModal() { $('modal').classList.add('hidden'); STATE.modalAction = null; }

$('m-cancel').onclick = closeModal;
$('m-ok').onclick = () => {
    const ma = STATE.modalAction;
    if (!ma) return closeModal();

    if (ma.kind === 'ticketReply') {
        const text = $('m-text').value.trim();
        if (text) post('ticket', { op: 'reply', id: ma.id, text });
        return closeModal();
    }

    const extra = {};
    if (!$('m-reason-w').classList.contains('hidden')) extra.reason = $('m-reason').value.trim();
    if (!$('m-days-w').classList.contains('hidden')) extra.days = Number($('m-days').value) || 0;
    if (!$('m-text-w').classList.contains('hidden')) extra.text = $('m-text').value.trim();
    if (!$('m-ref-w').classList.contains('hidden')) {
        const ref = $('m-ref').value.trim();
        if (/^\d+$/.test(ref)) extra.banId = Number(ref);
        else extra.license = ref;
    }
    sendAction(ma.action, extra);
    closeModal();
};

/* ------------------------------------------------ developer */
$('dev-staff-go').onclick = () =>
    post('dev', { op: 'set_staff', targetSrc: Number($('dev-staff-src').value), grade: $('dev-staff-grade').value });
$('dev-res-go').onclick = () => post('dev', { op: 'restart_resource', name: $('dev-res').value.trim() });
$('dev-tp-go').onclick = () =>
    post('dev', { op: 'tp_coords', x: Number($('dev-x').value), y: Number($('dev-y').value), z: Number($('dev-z').value) });
$('dev-fill').onclick = async () => {
    const c = await post('mycoords');
    if (c && c.x != null) { $('dev-x').value = c.x; $('dev-y').value = c.y; $('dev-z').value = c.z; }
};
$('dev-info-go').onclick = () => post('dev', { op: 'server_info' });

/* ------------------------------------------------ misc wiring */
$('player-search').addEventListener('input', filterPlayers);
document.querySelectorAll('[data-refresh]').forEach((b) => {
    b.onclick = () => {
        const t = b.dataset.refresh;
        if (t === 'players') post('players');
        else if (t === 'tickets') post('ticket', { op: 'list' });
        else if (t === 'active') post('ticket', { op: 'listActive' });
    };
});

function hide() { $('wrap').classList.add('hidden'); closeModal(); }
$('close').onclick = () => { hide(); post('close'); };
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('wrap').classList.contains('hidden')) {
        if (!$('modal').classList.contains('hidden')) closeModal();
        else { hide(); post('close'); }
    }
});

let toastT;
function toast(text) {
    const el = $('toast');
    el.textContent = text;
    el.classList.remove('hidden');
    clearTimeout(toastT);
    toastT = setTimeout(() => el.classList.add('hidden'), 3200);
}

/* auto-refresh player list while on Players tab */
setInterval(() => {
    if (!$('wrap').classList.contains('hidden') && STATE.tab === 'players') post('players');
}, 5000);

/* ------------------------------------------------ client -> NUI */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        $('wrap').classList.remove('hidden');
        buildMenu(d.data || {});
    } else if (d.action === 'forceClose') {
        hide();
    } else if (d.action === 'result') {
        const r = d.data || {};
        toast(r.msg || (r.ok ? 'OK' : 'Eroare'));
        if (STATE.tab === 'players') post('players');
    } else if (d.action === 'toast') {
        toast(d.text || '');
    } else if (d.action === 'data') {
        const p = d.data || {};
        if (p.tab === 'players') renderPlayers(p.list);
        else if (p.tab === 'tickets') renderTickets(p.list);
        else if (p.tab === 'active') renderActive(p.list);
        else if (p.tab === 'developer') renderDevInfo(p.info);
    }
});
