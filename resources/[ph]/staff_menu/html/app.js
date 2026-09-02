/* staff_menu / html / app.js
   Sidebar: Home | Tickets | Active Tickets | Players | Dev Tools */
const RES = 'staff_menu';
function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));
}
const $ = (id) => document.getElementById(id);
const qsa = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[c]);
const tidy = (s) => String(s || '').replace('T', ' ').replace(/\..*$/, '').replace(/:\d\d$/, '');
function mono(name, cls) {
    const s = String(name || '?'); const ch = (s.trim()[0] || '?').toUpperCase();
    let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    return `<span class="mono ${cls || ''}" style="background:hsl(${Math.abs(h) % 360}deg 52% 42%)">${esc(ch)}</span>`;
}

const NAV = [
    { id: 'home', label: 'Home', perm: 'tab_home', icon: 'fa-house' },
    { id: 'tickets', label: 'Tickets', perm: 'tab_tickets', icon: 'fa-ticket' },
    { id: 'active', label: 'Active Tickets', perm: 'tab_active', icon: 'fa-inbox' },
    { id: 'players', label: 'Players', perm: 'tab_players', icon: 'fa-users' },
    { id: 'dev', label: 'Dev Tools', perm: 'tab_developer', icon: 'fa-screwdriver-wrench' },
];
const TYPE_LABEL = {
    question: 'Question', general: 'General Problem', highstaff: 'High Staff',
    bug: 'Bug', report: 'Report', refund: 'Refund',
};
const typeLabel = (t) => TYPE_LABEL[t] || (t ? String(t)[0].toUpperCase() + String(t).slice(1) : 'General');

const S = {
    perms: {}, grades: {}, gradeList: [], clothingPieces: [], ticketColors: {}, staffActions: [],
    me: {}, tab: 'home', players: [], ticketsList: [], activeList: [],
    playerDetail: null, ticketThread: null, threadFrom: 'tickets',
    home: { god: false, invis: false }, logTab: 'warns',
};
const typeColor = (t) => S.ticketColors[t] || '#eab308';

/* ============================================================ build */
function buildMenu(d) {
    Object.assign(S, {
        perms: d.perms || {}, grades: d.grades || {}, gradeList: d.gradeList || [],
        clothingPieces: d.clothingPieces || [], ticketColors: d.ticketColors || {},
        staffActions: d.staffActions || [], me: d.me || {},
        home: d.home || { god: false, invis: false },
        playerDetail: null, ticketThread: null,
    });

    const sv = d.server || {};
    if (sv.logo) $('sv-logo').src = sv.logo; else $('sv-logo').removeAttribute('src');
    $('sv-name').textContent = sv.name || 'Purple Havoc';

    $('me-ava').innerHTML = mono(S.me.name);
    $('me-name').textContent = S.me.name || '-';
    $('me-id').textContent = `[ID: ${S.me.id != null ? S.me.id : '-'}]`;
    $('me-grade').textContent = S.me.gradeLabel || 'Staff';
    $('me-grade').style.color = S.me.gradeColor || '#b98cff';

    const nav = $('nav'); nav.innerHTML = '';
    NAV.forEach((t) => {
        if (!S.perms[t.perm]) return;
        const b = document.createElement('button');
        b.dataset.tab = t.id;
        b.innerHTML = `<i class="fa-solid ${t.icon}"></i> ${esc(t.label)}`;
        b.onclick = () => showTab(t.id);
        nav.appendChild(b);
    });

    // dev grade select
    $('dev-staff-grade').innerHTML = '<option value="">— no staff —</option>' +
        Object.keys(S.grades).map((k) => `<option value="${esc(k)}">${esc(S.grades[k].label)}</option>`).join('');

    const want = NAV.find((t) => t.id === d.tab && S.perms[t.perm]);
    showTab(want ? want.id : (NAV.find((t) => S.perms[t.perm]) || { id: 'home' }).id);
}

/* ============================================================ tabs */
function showTab(id) {
    S.tab = id;
    qsa('#nav button').forEach((b) => b.classList.toggle('active', b.dataset.tab === id));
    qsa('.page').forEach((p) => p.classList.toggle('active', p.dataset.page === id));
    $('tb-title').textContent = (NAV.find((t) => t.id === id) || {}).label || 'Home';

    if (id === 'home') renderHome();
    else if (id === 'tickets') { if (!S.ticketThread) post('ticket', { op: 'list' }); else renderTicketsTab(); }
    else if (id === 'active') post('ticket', { op: 'listActive' });
    else if (id === 'players') { if (!S.playerDetail) post('players'); else renderPlayersTab(); }
    else if (id === 'dev') { renderDev(); post('dev', { op: 'server_info' }); }
}

/* ============================================================ HOME */
function renderHome() {
    $('home-cloth').innerHTML = S.clothingPieces.map((p) =>
        `<button data-piece="${esc(p.id)}"><i class="fa-solid fa-shirt"></i> ${esc(p.label)}</button>`).join('');
    qsa('#home-cloth button').forEach((b) => b.onclick = () => post('home', { op: 'cloth', pieceId: b.dataset.piece }));

    $('tg-god').classList.toggle('on', !!S.home.god);
    $('tg-god').querySelector('.state').textContent = S.home.god ? 'ON' : 'OFF';
    $('tg-invis').classList.toggle('on', !!S.home.invis);
    $('tg-invis').querySelector('.state').textContent = S.home.invis ? 'ON' : 'OFF';
}
$('tg-god').onclick = () => post('home', { op: 'godmode' });
$('tg-invis').onclick = () => post('home', { op: 'invis' });
$('tg-respawn').onclick = () => post('home', { op: 'respawn' });

/* ============================================================ TICKETS */
function chip(html, cls) { return `<span class="chip ${cls || ''}">${html}</span>`; }
function typeChip(t) { return `<span class="chip type" style="background:${typeColor(t)}">Type: ${esc(typeLabel(t))}</span>`; }

function ticketCardHtml(t, isActive) {
    const uid = t.user_id != null ? t.user_id : t.playerUserId;
    return `<div class="tcard">
        <div class="chips">
            ${chip(`Ticket ID: <b>#${esc(t.id)}</b>`)}
            ${typeChip(t.category)}
            ${chip(`Player ID: <b>${esc(uid)}</b>`)}
            ${chip(`Player Username: <b>${esc(t.username)}</b>`)}
            ${isActive ? '' : `<span class="chip">${esc(tidy(t.created_at))}</span>`}
        </div>
        ${isActive ? '' : `<div class="desc"><b>Description:</b> ${esc(t.message)}</div>`}
        <div class="acts"><button class="btn go" data-view="${esc(t.id)}"><i class="fa-solid fa-eye"></i> View</button></div>
    </div>`;
}

function renderTicketList(elId, list, isActive) {
    const el = $(elId);
    el.innerHTML = (list && list.length)
        ? list.map((t) => ticketCardHtml(t, isActive)).join('')
        : `<div class="empty"><i class="fa-solid fa-ticket"></i>${isActive ? 'No active tickets.' : 'No open tickets.'}</div>`;
    qsa('[data-view]', el).forEach((b) => b.onclick = () => openThread(Number(b.dataset.view)));
}

function openThread(id) {
    S.threadFrom = S.tab;
    post('ticketThread', { id });
}

function renderTicketsTab() {
    if (S.ticketThread) { $('tickets-list').classList.add('hidden'); $('tickets-thread').classList.remove('hidden'); renderThread(); }
    else { $('tickets-list').classList.remove('hidden'); $('tickets-thread').classList.add('hidden'); renderTicketList('tickets-list', S.ticketsList, false); }
}

function msgRow(r) {
    const staff = !!r.isStaff;
    const g = r.grade || {};
    const badge = staff
        ? `<span class="msg-badge staff" style="color:${esc(g.color || '#37ff00')}">${esc(g.label || 'Staff')}</span>`
        : `<span class="msg-badge creator">Creator</span>`;
    return `<div class="msg ${staff ? 'right' : 'left'}">
        <div class="msg-id">
            ${mono(r.authorName, 'msg-ava')}
            <span class="msg-name">${esc(r.authorName || '?')}</span>
            <span class="msg-uid">ID: ${esc(r.authorId != null ? r.authorId : '-')}</span>
            ${badge}
        </div>
        <div class="bubble">${esc(r.message || '')}</div>
        <div class="msg-time">${esc(tidy(r.createdAt))}</div>
    </div>`;
}

function renderThread() {
    const th = S.ticketThread;
    const active = th.status === 'active';
    const acts = active
        ? `<button class="btn" data-a="goto"><i class="fa-solid fa-location-arrow"></i> Goto</button>
           <button class="btn danger" data-a="close"><i class="fa-solid fa-lock"></i> Close Ticket</button>
           <button class="btn ghost" data-a="back">Back to Tickets list</button>`
        : `<button class="btn green" data-a="accept"><i class="fa-solid fa-check"></i> Accept</button>
           <button class="btn ghost" data-a="back">Back to Tickets list</button>`;

    const replies = th.replies || [];
    $('tickets-thread').innerHTML = `
        <div class="thread-head">
            <div class="chips">
                ${chip(`Ticket ID: <b>#${esc(th.id)}</b>`)}
                ${chip(`Player ID: <b>${esc(th.playerUserId)}</b>`)}
                ${chip(`Player Username: <b>${esc(th.playerName)}</b>`)}
                ${chip(`Warns: <b>${esc(th.playerWarns || 0)}/3</b>`)}
                ${typeChip(th.category)}
            </div>
            <div class="acts">${acts}</div>
        </div>
        <div class="thread-desc"><b>Description:</b> ${esc(th.message)}</div>
        <div class="chat" id="thread-chat">
            ${replies.length ? replies.map(msgRow).join('') : '<div class="chat-empty">No messages yet.</div>'}
        </div>
        <div class="composer">
            ${active
                ? `<div class="cline">
                       <textarea class="inp" id="thread-input" rows="2" maxlength="250" placeholder="Message the player…"></textarea>
                       <button class="btn go" id="thread-send"><i class="fa-solid fa-paper-plane"></i> Send</button>
                   </div>`
                : `<div class="hint">Accept the ticket to start chatting with the player.</div>`}
        </div>`;

    const chat = $('thread-chat'); chat.scrollTop = chat.scrollHeight;

    qsa('#tickets-thread [data-a]').forEach((b) => b.onclick = () => {
        const a = b.dataset.a;
        if (a === 'back') { S.ticketThread = null; showTab(S.threadFrom || 'tickets'); return; }
        if (a === 'accept') { post('ticket', { op: 'accept', id: th.id }); setTimeout(() => post('ticketThread', { id: th.id }), 150); return; }
        if (a === 'goto') { post('ticket', { op: 'goto', id: th.id }); return; }
        if (a === 'close') { post('ticket', { op: 'close', id: th.id }); S.ticketThread = null; showTab(S.threadFrom || 'tickets'); return; }
    });
    const send = $('thread-send');
    if (send) {
        const fire = () => {
            const inp = $('thread-input'); const text = inp.value.trim();
            if (!text) return;
            post('ticket', { op: 'reply', id: th.id, text });
            inp.value = '';
            setTimeout(() => post('ticketThread', { id: th.id }), 150);
        };
        send.onclick = fire;
        $('thread-input').addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); fire(); }
        });
    }
}

/* ============================================================ ACTIVE */
function renderActiveTab() { renderTicketList('active-list', S.activeList, true); }

/* ============================================================ PLAYERS */
$('player-search').addEventListener('input', renderPlayersList);
$('player-open-id').onclick = () => {
    const v = Number($('player-search').value.trim());
    if (v) post('player', { op: 'get', id: v });
};

function renderPlayersTab() {
    if (S.playerDetail) { $('players-browse').classList.add('hidden'); $('player-detail').classList.remove('hidden'); renderPlayerDetail(); }
    else { $('players-browse').classList.remove('hidden'); $('player-detail').classList.add('hidden'); renderPlayersList(); }
}

function renderPlayersList() {
    const q = $('player-search').value.trim().toLowerCase();
    const rows = (S.players || []).filter((p) => !q || String(p.id).includes(q) || String(p.name || '').toLowerCase().includes(q));
    $('players-list').innerHTML = rows.map((p) => `
        <div class="tcard" style="cursor:pointer" data-pid="${esc(p.id)}">
            <div class="chips">
                ${mono(p.name)}
                ${chip(`<b>${esc(p.name)}</b>`)}
                ${chip(`ID: <b>${esc(p.id)}</b>`)}
                ${p.staffLabel ? `<span class="chip" style="color:${esc(p.staffColor || '#b98cff')}">${esc(p.staffLabel)}</span>` : ''}
                <span class="chip">${esc(p.ping)}ms</span>
            </div>
        </div>`).join('') || '<div class="empty"><i class="fa-solid fa-users"></i>No matching online players. Use "Open by ID".</div>';
    qsa('[data-pid]', $('players-list')).forEach((el) => el.onclick = () => post('player', { op: 'get', id: Number(el.dataset.pid) }));
}

const LOG_TABS = [
    { id: 'warns', label: 'Warns Log' }, { id: 'kicks', label: 'Kick Logs' },
    { id: 'bans', label: 'Ban Logs' }, { id: 'chats', label: 'Chat Logs' },
];
function logRowHtml(kind, r) {
    if (kind === 'warns') return `<div class="logrow"><div class="lr-top"><b>${esc(r.warned_by_name || '—')}</b><span>${esc(tidy(r.created_at))}</span></div>${esc(r.reason)}</div>`;
    if (kind === 'kicks') return `<div class="logrow"><div class="lr-top"><b>${esc(r.staff_name || '—')}</b><span>${esc(tidy(r.created_at))}</span></div>${esc(r.detail || '')}</div>`;
    if (kind === 'bans') return `<div class="logrow"><div class="lr-top"><b>${esc(r.banned_by_name || '—')}</b><span>${esc(tidy(r.created_at))}${Number(r.active) ? ' · ACTIVE' : ''}</span></div>${esc(r.reason)}</div>`;
    return `<div class="logrow"><div class="lr-top"><span></span><span>${esc(tidy(r.created_at))}</span></div>${esc(r.message)}</div>`;
}
function renderLogRows() {
    const d = S.playerDetail; if (!d) return;
    const kind = S.logTab;
    const list = (d.logs && d.logs[kind]) || [];
    qsa('.logtabs button').forEach((b) => b.classList.toggle('active', b.dataset.k === kind));
    $('pd-logrows').innerHTML = list.length ? list.map((r) => logRowHtml(kind, r)).join('') : `<div class="chat-empty">No ${kind}.</div>`;
}

function actBox(title, icon, fields, action, btnCls) {
    const rows = [];
    if (fields.days) rows.push(`<input class="inp d" type="number" min="0" value="0" placeholder="days" title="0 = permanent" />`);
    if (fields.reason) rows.push(`<input class="inp r" placeholder="reason" />`);
    return `<div class="actbox" data-action="${action}">
        <h4><i class="fa-solid ${icon}"></i> ${title}</h4>
        <div class="r">${rows.join('')}</div>
        <button class="btn ${btnCls || 'go'} run">${title}</button>
    </div>`;
}

function renderPlayerDetail() {
    const d = S.playerDetail;
    const p = S.perms;
    const boxes = [];
    if (p.warn) boxes.push(actBox('Warn', 'fa-triangle-exclamation', { reason: true }, 'warn'));
    if (p.kick) boxes.push(actBox('Kick', 'fa-user-slash', { reason: true }, 'kick', 'danger'));
    if (p.ban) boxes.push(actBox('Ban', 'fa-gavel', { days: true, reason: true }, 'ban', 'danger'));
    if (p.ban_offline) boxes.push(actBox('Ban Offline', 'fa-gavel', { days: true, reason: true }, 'ban_offline', 'danger'));
    if (p.unban) boxes.push(actBox('Unban', 'fa-unlock', { reason: true }, 'unban', 'green'));

    const quick = (S.staffActions || []).filter((a) =>
        a.needsTarget && !a.needsReason && !a.needsDays && !a.needsText && !a.needsRef && S.perms[a.id]);

    $('player-detail').innerHTML = `
        <button class="btn ghost" id="pd-back"><i class="fa-solid fa-arrow-left"></i> Back to players</button>
        <div class="pd-head" style="margin-top:12px">
            ${mono(d.name)}
            <span class="pd-name">${esc(d.name)}</span>
            <span class="chip">ID: <b>${esc(d.id)}</b></span>
            <span class="chip" style="color:${esc(d.staffColor)}"><b>${esc(d.staffLabel)}</b></span>
            ${d.online ? '<span class="chip" style="color:#56d98a"><b>ONLINE</b></span>' : '<span class="chip"><b>offline</b></span>'}
        </div>
        <div class="pd-sub">
            <span class="chip">Faction: <b>${esc(d.faction || 'None')}</b></span>
            <span class="chip">Faction Rank: <b>${esc(d.factionRank || '—')}</b></span>
            <span class="chip">Warns: <b>${esc(d.warns || 0)}/3</b></span>
        </div>

        <div class="card">
            <div class="logtabs">${LOG_TABS.map((t) => `<button data-k="${t.id}">${t.label}</button>`).join('')}</div>
            <div class="logrows" id="pd-logrows"></div>
        </div>

        ${(boxes.length || quick.length) ? `<div class="card">
            <h3><i class="fa-solid fa-shield"></i> Actions</h3>
            ${quick.length ? `<div class="quick" style="margin-bottom:12px">${quick.map((a) =>
                `<button class="btn" data-quick="${a.id}">${esc(a.label)}</button>`).join('')}</div>` : ''}
            <div class="actgrid">${boxes.join('')}</div>
        </div>` : ''}`;

    $('pd-back').onclick = () => { S.playerDetail = null; post('players'); };
    qsa('.logtabs button').forEach((b) => b.onclick = () => { S.logTab = b.dataset.k; renderLogRows(); });
    renderLogRows();

    qsa('#player-detail .actbox .run').forEach((btn) => btn.onclick = () => {
        const box = btn.closest('.actbox');
        const action = box.dataset.action;
        const reason = (box.querySelector('.r') || {}).value ? box.querySelector('.r').value.trim() : '';
        const daysEl = box.querySelector('.d');
        const days = daysEl ? Number(daysEl.value) || 0 : 0;
        post('pmod', { action, targetId: d.id, reason, days });
    });
    qsa('#player-detail [data-quick]').forEach((b) => b.onclick = () =>
        post('action', { action: b.dataset.quick, targetId: d.id }));
}

/* ============================================================ DEV */
function renderDev() {
    $('dev-cloth').innerHTML = (S.gradeList || []).map((g) => `
        <div class="dev-cloth-row">
            <span class="g" style="color:${esc(g.color)}">${esc(g.label)}</span>
            <span class="pcs">${S.clothingPieces.map((p) =>
                `<button data-grade="${esc(g.key)}" data-piece="${esc(p.id)}">${esc(p.label)}</button>`).join('')}</span>
        </div>`).join('') || '<div class="chat-empty">No grades.</div>';
    qsa('#dev-cloth button').forEach((b) => b.onclick = () =>
        post('home', { op: 'cloth', pieceId: b.dataset.piece, grade: b.dataset.grade }));
}
$('dev-staff-go').onclick = () => post('dev', { op: 'set_staff', targetId: Number($('dev-staff-src').value), grade: $('dev-staff-grade').value });
$('dev-res-go').onclick = () => post('dev', { op: 'restart_resource', name: $('dev-res').value.trim() });
$('dev-tp-go').onclick = () => post('dev', { op: 'tp_coords', x: Number($('dev-x').value), y: Number($('dev-y').value), z: Number($('dev-z').value) });
$('dev-fill').onclick = async () => {
    const c = await post('mycoords');
    if (c && c.x != null) { $('dev-x').value = c.x; $('dev-y').value = c.y; $('dev-z').value = c.z; }
};
$('dev-info-go').onclick = () => post('dev', { op: 'server_info' });
function renderDevInfo(info) {
    if (!info) return;
    const up = info.uptime || 0, h = Math.floor(up / 3600), m = Math.floor((up % 3600) / 60);
    $('dev-info').innerHTML = `Uptime: ${h}h ${m}m<br>Players: ${info.players} / ${info.maxPlayers}<br>Resources: ${info.resources}`;
}

/* ============================================================ toast + noclip */
let toastT;
function toast(text) {
    const el = $('toast'); el.textContent = text; el.classList.remove('hidden');
    clearTimeout(toastT); toastT = setTimeout(() => el.classList.add('hidden'), 3200);
}
function renderNoclip(n) {
    const hud = $('noclip-hud'); if (!hud) return;
    if (!n.on) { hud.classList.add('hidden'); return; }
    hud.classList.remove('hidden');
    if ($('nc-speed-name')) $('nc-speed-name').textContent = n.speedName || '?';
    if ($('nc-speed-lbl')) $('nc-speed-lbl').textContent = n.speedLabel ? '· ' + n.speedLabel : '';
    if ($('nc-tiers')) $('nc-tiers').innerHTML = (n.tiers || []).map((t) =>
        `<span class="t${t.active ? ' active' : ''}">${esc(t.name)}</span>`).join('');
}

/* ============================================================ show / hide */
function hide() { $('wrap').classList.add('hidden'); }

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('wrap').classList.contains('hidden')) return;
    if (S.ticketThread) { S.ticketThread = null; showTab(S.threadFrom || 'tickets'); return; }
    if (S.playerDetail) { S.playerDetail = null; renderPlayersTab(); return; }
    hide(); post('close');
});

/* ============================================================ message bus */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        $('wrap').classList.remove('hidden');
        buildMenu(d.data || {});
    } else if (d.action === 'forceClose') {
        hide();
    } else if (d.action === 'result') {
        const r = d.data || {};
        if (r.msg) toast(r.msg);
    } else if (d.action === 'toast') {
        toast(d.text || '');
    } else if (d.action === 'noclip') {
        renderNoclip(d.data || {});
    } else if (d.action === 'data') {
        const p = d.data || {};
        if (p.tab === 'players') { S.players = p.list || []; if (S.tab === 'players' && !S.playerDetail) renderPlayersList(); }
        else if (p.tab === 'tickets') { S.ticketsList = p.list || []; if (S.tab === 'tickets' && !S.ticketThread) renderTicketsTab(); }
        else if (p.tab === 'active') { S.activeList = p.list || []; if (S.tab === 'active') renderActiveTab(); }
        else if (p.tab === 'playerDetail') { S.playerDetail = p.detail; if (S.tab !== 'players') showTab('players'); else renderPlayersTab(); }
        else if (p.tab === 'ticketThread') { S.ticketThread = p.thread; if (S.tab !== 'tickets') showTab('tickets'); else renderTicketsTab(); }
        else if (p.tab === 'home') { S.home = p.state || S.home; if (S.tab === 'home') renderHome(); }
        else if (p.tab === 'developer') renderDevInfo(p.info);
    }
});
