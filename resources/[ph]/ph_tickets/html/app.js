/* ph_tickets / html / app.js
   #tk -> /ticket menu : Create Ticket | My Tickets (+ live chat with staff)
   NUI bus: inbound {action:'open'|'data'|'forceClose', data}
            outbound post('action', {op,...}), post('close') */
const RES = 'ph_tickets';
function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));
}
const $ = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[c]);
function monogram(name, cls) {
    const s = String(name || '?');
    const ch = (s.trim()[0] || '?').toUpperCase();
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    return `<span class="${cls || 'tk-ava'}" style="background:hsl(${Math.abs(h) % 360}deg 52% 42%)">${esc(ch)}</span>`;
}
const tidy = (t) => String(t || '').replace('T', ' ').replace(/\..*$/, '').replace(/:\d\d$/, '');

const S = { data: null, tab: 'create', selType: null, viewing: false, pollT: null, firstOpen: true };
const act = (payload) => post('action', payload);
const MAXLEN = () => (S.data && S.data.maxLen) || 250;

/* ============================================================ nav / tabs */
function setTab(tab) {
    S.tab = tab;
    if (tab !== 'mytickets') stopPoll(), S.viewing = false;
    $$('#tk .tk-nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    $$('#tk .tk-panel').forEach((p) => p.classList.toggle('active', p.id === 'panel-' + tab));
    if (tab === 'create') renderCreate();
    else renderMyTickets();
}

/* ============================================================ header */
function renderHead() {
    const sv = (S.data && S.data.server) || {};
    const logo = $('#tk-logo');
    if (sv.logo) logo.src = sv.logo; else logo.removeAttribute('src');
    $('#tk-server').textContent = sv.name || 'Purple Havoc';
}

/* ============================================================ Create Ticket */
function renderCreate() {
    const hasTicket = !!(S.data && S.data.ticket);
    $('#create-locked').classList.toggle('hidden', !hasTicket);
    $('#create-form').classList.toggle('hidden', hasTicket);
    if (hasTicket) return;

    const types = (S.data && S.data.types) || [];
    $('#tk-types').innerHTML = types.map((t) => `
        <button class="tk-type${S.selType === t.id ? ' selected' : ''}" data-type="${esc(t.id)}">
            <span class="ic"><i class="fa-solid ${esc(t.icon || 'fa-circle-question')}"></i></span>
            <span class="nm">${esc(t.label)}</span>
            <span class="ds">${esc(t.desc || '')}</span>
        </button>`).join('');
    $$('#tk-types .tk-type').forEach((b) => b.onclick = () => {
        S.selType = b.dataset.type;
        renderCreate();
    });

    const ta = $('#tk-desc');
    ta.maxLength = MAXLEN();
    updateCount(ta, $('#tk-desc-count'));
    refreshSubmit();
}

function updateCount(ta, label) {
    const n = ta.value.length, max = MAXLEN();
    label.textContent = `${n} / ${max}`;
    label.classList.toggle('over', n >= max);
}
function refreshSubmit() {
    $('#tk-submit').disabled = !(S.selType && $('#tk-desc').value.trim().length >= 3);
}

$('#tk-desc').addEventListener('input', () => { updateCount($('#tk-desc'), $('#tk-desc-count')); refreshSubmit(); });
$('#tk-submit').onclick = () => {
    const description = $('#tk-desc').value.trim();
    if (!S.selType || description.length < 3) return;
    $('#tk-submit').disabled = true;
    act({ op: 'create', typeId: S.selType, description });
};

/* ============================================================ My Tickets */
function renderMyTickets() {
    const t = S.data && S.data.ticket;
    $('#mt-empty').classList.toggle('hidden', !!t);
    $('#mt-card').classList.toggle('hidden', !t || S.viewing);
    $('#mt-chat').classList.toggle('hidden', !t || !S.viewing);
    if (!t) { S.viewing = false; stopPoll(); return; }

    if (S.viewing) { renderChat(); return; }

    $('#tc-id').textContent = '#' + t.id;
    $('#tc-type').textContent = t.typeLabel || t.type || '—';
    $('#tc-staff').textContent = t.assignedName || 'Not yet accepted';
    $('#tc-staffid').textContent = t.assignedId != null ? t.assignedId : '—';
}

$('#tc-view').onclick = () => { S.viewing = true; renderMyTickets(); startPoll(); };
$('#chat-back').onclick = () => { S.viewing = false; stopPoll(); renderMyTickets(); };
$('#chat-close').onclick = () => {
    if (!S.data || !S.data.ticket) return;
    act({ op: 'closeOwn' });
};

function renderChat() {
    const t = S.data.ticket;
    if (!t) { S.viewing = false; renderMyTickets(); return; }
    const me = (S.data.me && S.data.me.id);

    $('#chat-title').textContent = `Ticket #${t.id} · ${esc(t.typeLabel || t.type || '')}`;
    const st = $('#chat-status');
    st.textContent = t.status;
    st.className = 'tk-status ' + t.status;

    const box = $('#chat-messages');
    const nearBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 60;

    const rows = [];
    // original description as the first "creator" message
    rows.push(msgRow({
        authorName: (S.data.me && S.data.me.name) || 'You',
        isStaff: false, message: t.message, createdAt: t.createdAt,
    }, false));
    (t.replies || []).forEach((r) => rows.push(msgRow(r, r.isStaff)));
    box.innerHTML = rows.join('') || `<div class="tk-msg-empty">No messages yet.</div>`;
    if (nearBottom) box.scrollTop = box.scrollHeight;

    const active = t.status === 'active';
    const input = $('#chat-input');
    input.disabled = !active;
    input.maxLength = MAXLEN();
    $('#chat-send').disabled = !active || input.value.trim().length < 1;
    $('#chat-hint').classList.toggle('hidden', active || t.status === 'closed');
    if (t.status === 'closed') {
        $('#chat-hint').textContent = 'This ticket is closed.';
        $('#chat-hint').classList.remove('hidden');
    } else if (!active) {
        $('#chat-hint').textContent = 'Waiting for a staff member to accept your ticket…';
    }
    updateCount(input, $('#chat-count'));
    $('#chat-close').classList.toggle('hidden', t.status === 'closed');
}

function msgRow(r, staff) {
    const side = staff ? 'right' : 'left';
    let badge;
    if (staff) {
        const g = r.grade || {};
        badge = `<span class="tk-badge staff" style="color:${esc(g.color || '#37ff00')}">${esc(g.label || 'Staff')}</span>`;
    } else {
        badge = `<span class="tk-badge creator">Ticket Creator</span>`;
    }
    return `<div class="tk-msg ${side}">
        <div class="tk-msg-id">
            ${monogram(r.authorName)}
            <span class="tk-msg-name">${esc(r.authorName || '?')}</span>
            ${badge}
        </div>
        <div class="tk-bubble">${esc(r.message || '')}</div>
        <div class="tk-msg-time">${esc(tidy(r.createdAt))}</div>
    </div>`;
}

$('#chat-input').addEventListener('input', () => {
    updateCount($('#chat-input'), $('#chat-count'));
    const t = S.data && S.data.ticket;
    $('#chat-send').disabled = !(t && t.status === 'active') || $('#chat-input').value.trim().length < 1;
});
$('#chat-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#chat-send').click(); }
});
$('#chat-send').onclick = () => {
    const text = $('#chat-input').value.trim();
    const t = S.data && S.data.ticket;
    if (!text || !t || t.status !== 'active') return;
    act({ op: 'reply', text });
    $('#chat-input').value = '';
    updateCount($('#chat-input'), $('#chat-count'));
    $('#chat-send').disabled = true;
};

/* ============================================================ live poll */
function startPoll() {
    stopPoll();
    const secs = (S.data && S.data.poll) || 3;
    S.pollT = setInterval(() => act({ op: 'refresh' }), Math.max(2, secs) * 1000);
}
function stopPoll() { if (S.pollT) { clearInterval(S.pollT); S.pollT = null; } }

/* ============================================================ nav wiring */
$$('#tk .tk-nav-btn').forEach((b) => b.onclick = () => setTab(b.dataset.tab));

/* ============================================================ message bus */
function onOpen(data) {
    S.data = data || {};
    renderHead();
    if (S.firstOpen) {
        S.firstOpen = false;
        S.tab = S.data.ticket ? 'mytickets' : 'create';
    }
    setTab(S.tab);
}
function onData(data) {
    const hadTicket = !!(S.data && S.data.ticket);
    S.data = data || {};
    renderHead();
    // just created a ticket -> jump to My Tickets
    if (!hadTicket && S.data.ticket && S.tab === 'create') { setTab('mytickets'); return; }
    if (S.tab === 'create') renderCreate();
    else renderMyTickets();
}

window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') { $('#tk').classList.remove('hidden'); onOpen(d.data); }
    else if (d.action === 'data') { onData(d.data); }
    else if (d.action === 'forceClose') { stopPoll(); $('#tk').classList.add('hidden'); }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (S.viewing) { S.viewing = false; stopPoll(); renderMyTickets(); return; }
    stopPoll();
    post('close').then(() => $('#tk').classList.add('hidden'));
});
