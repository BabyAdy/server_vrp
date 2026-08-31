/* ph_factions / html / app.js */
const RES = 'ph_factions';
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

const S = { data: null, tab: 'members', vcat: 'car', memSearch: '' };

function op(payload) { post('menu', payload); }

/* ---------------------------------------------------- tabs */
function buildTabs() {
    const role = S.data.role || {};
    const tabs = [
        { id: 'members', label: 'Membri', show: true },
        { id: 'vehicles', label: 'Vehicule', show: !!S.data.faction },
        { id: 'ranks', label: 'Rank-uri', show: !!S.data.faction && role.isLeader },
        { id: 'dev', label: 'Developer', show: !!role.isDev },
    ].filter((t) => t.show);
    if (!tabs.find((t) => t.id === S.tab)) S.tab = tabs[0] ? tabs[0].id : 'members';

    $('#tabs').innerHTML = tabs.map((t) =>
        `<button data-tab="${t.id}" class="${t.id === S.tab ? 'active' : ''}">${t.label}</button>`).join('');
    $$('#tabs button').forEach((b) => b.onclick = () => { S.tab = b.dataset.tab; render(); });
    $$('.tab').forEach((s) => s.classList.toggle('active', s.dataset.tab === S.tab));
}

/* ---------------------------------------------------- members */
function memberActions(mem) {
    const role = S.data.role || {};
    const eff = role.effRank || 0;
    const canAct = role.canManage && eff > mem.rank && mem.id !== undefined;
    const out = [];
    if (canAct && eff > mem.rank + 1) out.push(`<button class="btn mini" data-a="promote" data-u="${mem.id}">+</button>`);
    if (canAct && mem.rank > 1) out.push(`<button class="btn mini" data-a="demote" data-u="${mem.id}">-</button>`);
    if (canAct) out.push(`<button class="btn mini" data-a="warn" data-u="${mem.id}">Warn</button>`);
    if (canAct && mem.warns > 0) out.push(`<button class="btn mini" data-a="unwarn" data-u="${mem.id}">-Warn</button>`);
    if (role.rank >= 6 || role.supervisor) out.push(`<button class="btn mini" data-a="toggleTester" data-u="${mem.id}">Tester</button>`);
    if (role.rank >= 6) out.push(`<button class="btn mini" data-a="toggleSupervisor" data-u="${mem.id}">Sup</button>`);
    if (role.isLeader && mem.rank < 7) out.push(`<button class="btn mini" data-a="transferLeader" data-u="${mem.id}">→ Leader</button>`);
    if (canAct) out.push(`<button class="btn mini danger" data-a="kick" data-u="${mem.id}">Kick</button>`);
    return out.join('');
}

function renderMembers() {
    const fac = S.data.faction || {};
    const ranks = fac.ranks || [];
    const q = S.memSearch.toLowerCase();
    const list = (S.data.members || []).filter((m) => !q || String(m.name).toLowerCase().includes(q));
    $('#members').innerHTML = list.map((m) => {
        const badges = [];
        if (m.rank >= 7) badges.push('<span class="b">Leader</span>');
        else if (m.rank === 6) badges.push('<span class="b">Co-Leader</span>');
        if (m.supervisor) badges.push('<span class="b">Supervisor</span>');
        if (m.tester) badges.push('<span class="b">Tester</span>');
        if (m.warns > 0) badges.push(`<span class="b warn">${m.warns}/${S.data.maxWarns} warn</span>`);
        if (!m.online) badges.push('<span class="b off">offline</span>');
        return `<div class="mrow">
            <span class="nm">${esc(m.name)}</span>
            <span class="rk">${esc(ranks[m.rank - 1] || ('Rank ' + m.rank))}</span>
            <span class="badges">${badges.join('')}</span>
            <span class="grow"></span>
            <span class="acts">${memberActions(m)}</span>
        </div>`;
    }).join('') || '<div class="muted">Niciun membru.</div>';

    $$('#members [data-a]').forEach((b) => b.onclick = () => {
        const a = b.dataset.a, u = Number(b.dataset.u);
        if (a === 'warn' || a === 'kick') {
            const reason = prompt(a === 'warn' ? 'Motiv warn:' : 'Motiv kick:') || '';
            if (a === 'kick' && !confirm('Sigur dai kick?')) return;
            op({ op: a, userId: u, reason });
        } else {
            op({ op: a, userId: u });
        }
    });
}

/* ---------------------------------------------------- vehicles */
function renderVehicles() {
    const role = S.data.role || {};
    const canEdit = (role.rank || 0) >= 6;
    $('#veh-add').classList.toggle('hidden', !canEdit);
    $$('.vcat').forEach((b) => b.classList.toggle('active', b.dataset.cat === S.vcat));

    const arr = (S.data.vehicles && S.data.vehicles[S.vcat]) || [];
    $('#vehicles').innerHTML = arr.map((v) => `
        <div class="vrow">
            <span class="grow">
                <span class="lb">${esc(v.label)}</span>
                <span class="md"> — ${esc(v.model)}</span>
            </span>
            ${canEdit
                ? `<input type="number" min="1" max="7" value="${v.minRank || 1}" data-vr="${v.id}" title="rank minim" />
                   <button class="btn mini danger" data-vd="${v.id}">Sterge</button>`
                : `<span class="md">rank ${v.minRank || 1}+</span>`}
        </div>`).join('') || '<div class="muted">Niciun vehicul in aceasta categorie.</div>';

    $$('#vehicles [data-vd]').forEach((b) => b.onclick = () => {
        if (confirm('Stergi vehiculul?')) op({ op: 'removeVehicle', vehId: Number(b.dataset.vd) });
    });
    $$('#vehicles [data-vr]').forEach((inp) => inp.onchange = () => {
        op({ op: 'setVehicleRank', vehId: Number(inp.dataset.vr), minRank: Number(inp.value) });
    });
}

/* ---------------------------------------------------- ranks */
function renderRanks() {
    const ranks = (S.data.faction && S.data.faction.ranks) || [];
    let h = '';
    for (let i = 1; i <= (S.data.rankCount || 7); i++) {
        h += `<label>Rank ${i}${i === 7 ? ' (Leader)' : i === 6 ? ' (Co-Leader)' : ''}
            <input data-ri="${i}" maxlength="32" value="${esc(ranks[i - 1] || ('Rank ' + i))}" /></label>`;
    }
    $('#ranks').innerHTML = h;
}

/* ---------------------------------------------------- dev */
function renderDev() {
    const facs = S.data.allFactions || [];
    $('#dev-fac').innerHTML = facs.map((f) =>
        `<option value="${f.id}">#${f.id} ${esc(f.name)}${f.active ? '' : ' (inactiv)'}</option>`).join('')
        || '<option value="">— nicio factiune —</option>';
    if (S.data.faction) {
        const cur = $('#dev-fac').querySelector(`option[value="${S.data.faction.id}"]`);
        if (cur) $('#dev-fac').value = S.data.faction.id;
    }
}
function devFac() { return Number($('#dev-fac').value) || (S.data.faction && S.data.faction.id) || 0; }

/* ---------------------------------------------------- render */
function render() {
    if (!S.data) return;
    const fac = S.data.faction;
    $('#f-name').textContent = fac ? fac.name : 'Fara factiune';
    const role = S.data.role || {};
    const roleTxt = role.isLeader ? 'Leader' : role.rank === 6 ? 'Co-Leader'
        : role.supervisor ? 'Supervisor' : role.tester ? 'Tester'
        : role.rank ? (role.rankName || ('Rank ' + role.rank)) : (role.isDev ? 'Developer' : '');
    $('#f-role').textContent = roleTxt;

    buildTabs();
    if (S.tab === 'members') renderMembers();
    else if (S.tab === 'vehicles') renderVehicles();
    else if (S.tab === 'ranks') renderRanks();
    else if (S.tab === 'dev') renderDev();
}

/* ---------------------------------------------------- static wiring */
$('#close').onclick = () => post('close').then(() => hide());
$('#g-close').onclick = () => post('close').then(() => $('#garage').classList.add('hidden'));

$('#mem-search').addEventListener('input', (e) => { S.memSearch = e.target.value; renderMembers(); });
$('#recruit').onclick = async () => {
    const r = await post('nearestPlayer');
    if (r && r.serverId) op({ op: 'recruit', serverId: r.serverId });
    else alert('Niciun jucator langa tine (5m).');
};

$$('.vcat').forEach((b) => b.onclick = () => { S.vcat = b.dataset.cat; renderVehicles(); });
$('#va-go').onclick = () => {
    const model = $('#va-model').value.trim();
    if (!model) return;
    op({ op: 'addVehicle', category: S.vcat, model, label: $('#va-label').value.trim() || model, minRank: Number($('#va-rank').value) || 1 });
    $('#va-model').value = ''; $('#va-label').value = '';
};

$('#ranks-save').onclick = () => {
    $$('#ranks input').forEach((inp) => {
        op({ op: 'setRankName', index: Number(inp.dataset.ri), name: inp.value.trim() });
    });
};

$('#dev-create').onclick = () => {
    const n = $('#dev-name').value.trim();
    if (n.length >= 3) { op({ op: 'createFaction', name: n }); $('#dev-name').value = ''; }
};
$('#dev-delete').onclick = () => {
    if (confirm('STERGI definitiv factiunea si scoti toti membrii?')) op({ op: 'deleteFaction', factionId: devFac() });
};
$$('.dev-points button').forEach((b) => b.onclick = () =>
    op({ op: 'setPoint', factionId: devFac(), what: b.dataset.point }));
$('#dev-setleader').onclick = () => op({ op: 'setLeader', factionId: devFac(), userId: Number($('#dev-leader').value) });
$('#dev-setmanager').onclick = () => op({ op: 'setManager', factionId: devFac(), userId: Number($('#dev-manager').value) });
$('#dev-seed').onclick = () => op({ op: 'seedVanilla', factionId: devFac(), minRank: Number($('#dev-seedrank').value) || 3 });

/* ---------------------------------------------------- garage */
function renderGarage(d) {
    $('#g-title').textContent = ({ car: 'Garaj Auto', heli: 'Helipad', boat: 'Doc Barci' })[d.category] || 'Garaj';
    $('#g-list').innerHTML = (d.list || []).map((v) => `
        <div class="grow-veh" data-id="${v.id}">
            <span>${esc(v.label)} <span class="md">(${esc(v.model)})</span></span>
            <span class="md">rank ${v.minRank || 1}+</span>
        </div>`).join('') || '<div class="muted">Niciun vehicul disponibil pentru rank-ul tau.</div>';
    $$('#g-list [data-id]').forEach((el) => el.onclick = () => {
        post('garagePick', { id: Number(el.dataset.id) });
        $('#garage').classList.add('hidden');
    });
}

/* ---------------------------------------------------- show/hide */
function hide() { $('#menu').classList.add('hidden'); }

window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        S.data = d.data;
        $('#menu').classList.remove('hidden');
        render();
    } else if (d.action === 'data') {
        S.data = d.data;
        render();
    } else if (d.action === 'garage') {
        renderGarage(d.data || {});
        $('#garage').classList.remove('hidden');
    } else if (d.action === 'forceClose') {
        hide();
        $('#garage').classList.add('hidden');
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (!$('#garage').classList.contains('hidden')) { post('close'); $('#garage').classList.add('hidden'); return; }
        if (!$('#menu').classList.contains('hidden')) { post('close').then(hide); }
    }
});
