/* ph_factions / html / app.js
   #menu    -> Faction Menu   (/factionmenu)     : Members | Logs
   #devmenu -> Dev Faction Menu (/devfactionmenu) : Create Faction | Edit Faction
   #garage  -> vehicle picker (unchanged) */
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

const S = { data: null, mtab: 'members', memSearch: '', dev: null, dtab: 'create', efcat: 'car' };

const mop = (payload) => post('menu', payload);
const dop = (payload) => post('devMenu', Object.assign({ factionId: efFactionId() }, payload));

/* ============================================================ shared bits */
function monogram(name) {
    const s = String(name || '?');
    const ch = (s.trim()[0] || '?').toUpperCase();
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    const hue = Math.abs(h) % 360;
    return `<span class="mono" style="background:hsl(${hue}deg 52% 42%)">${esc(ch)}</span>`;
}
function badgeHtml(key) {
    if (!key) return '';
    const b = (S.data && S.data.badges && S.data.badges[key]) || null;
    if (!b) return `<span class="bdg">${esc(key)}</span>`;
    return `<span class="bdg" style="color:${esc(b.color)}">${esc(b.icon || '')} ${esc(b.label)}</span>`;
}
const prettyAction = (a) => String(a || '').replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

/* ============================================================ FACTION MENU */
function memberActions(m) {
    const role = S.data.role || {};
    const rc = S.data.rankCoLeader || 6;
    const rl = S.data.rankLeader || 7;
    const out = [];
    // rank up / rank down: Leader only (faction_rank == 7), not on self
    if (role.isLeader && m.id !== undefined) {
        if (m.rank >= 1 && m.rank < rl - 1) out.push(`<button class="btn mini" data-a="promote" data-u="${m.id}">Rank +</button>`);
        if (m.rank > 1) out.push(`<button class="btn mini" data-a="demote" data-u="${m.id}">Rank -</button>`);
    }
    // tester / supervisor / warn: faction_rank >= 6
    if (role.canManage) {
        out.push(`<button class="btn mini" data-a="toggleTester" data-u="${m.id}">${m.tester ? 'Remove' : 'Promote'} Tester</button>`);
        out.push(`<button class="btn mini" data-a="toggleSupervisor" data-u="${m.id}">${m.supervisor ? 'Remove' : 'Promote'} Supervisor</button>`);
        out.push(`<button class="btn mini" data-a="warn" data-u="${m.id}">Give Warn</button>`);
        if (m.warns > 0) out.push(`<button class="btn mini" data-a="unwarn" data-u="${m.id}">Remove Warn</button>`);
    }
    return out.join('');
}

function renderMembers() {
    const fac = S.data.faction || {};
    const ranks = fac.ranks || [];
    const q = S.memSearch.toLowerCase();
    const list = (S.data.members || []).filter((m) => !q || String(m.name).toLowerCase().includes(q));
    $('#members').innerHTML = list.map((m) => {
        const rkName = ranks[m.rank - 1] || ('Rank ' + m.rank);
        const warnTag = m.warns > 0 ? ` <span class="wtag">${m.warns}/${S.data.maxWarns}</span>` : '';
        const offTag = m.online ? '' : ' <span class="wtag off">offline</span>';
        return `<div class="mrow">
            <span class="c-av">${monogram(m.name)}</span>
            <span class="c-nm">${esc(m.name)}${offTag}</span>
            <span class="c-dy">${Number(m.days || 0).toFixed(2)}</span>
            <span class="c-rk">${esc(rkName)} <span class="rn">(${m.rank})</span></span>
            <span class="c-bd">${badgeHtml(m.badge)}${warnTag}</span>
            <span class="grow"></span>
            <span class="c-ac">${memberActions(m)}</span>
        </div>`;
    }).join('') || '<div class="muted">No members.</div>';

    $$('#members [data-a]').forEach((b) => b.onclick = () => {
        const a = b.dataset.a, u = Number(b.dataset.u);
        if (a === 'warn') {
            const reason = prompt('Warn reason:') || '';
            mop({ op: 'warn', userId: u, reason });
        } else {
            mop({ op: a, userId: u });
        }
    });
}

function renderLogs() {
    const rows = S.data.logs || [];
    $('#logs').innerHTML = rows.map((r) => `
        <div class="lrow">
            <span class="l-tm">${esc(r.created_at || '')}</span>
            <span class="l-ac">${esc(r.actor_name || '—')}</span>
            <span class="l-at">${esc(prettyAction(r.action))}</span>
            <span class="l-tg">${esc(r.target_name || '—')}</span>
            <span class="l-dt">${esc(r.detail || '')}</span>
        </div>`).join('') || '<div class="muted">No logs.</div>';
}

function renderMenu() {
    if (!S.data) return;
    const fac = S.data.faction || {};
    const role = S.data.role || {};
    $('#f-name').textContent = fac.name || 'Faction Menu';
    $('#f-role').textContent = role.isLeader ? 'Leader'
        : role.rank === (S.data.rankCoLeader || 6) ? 'Co-Leader'
        : (role.rankName || ('Rank ' + role.rank));

    $$('#menu .tabs button').forEach((b) => b.classList.toggle('active', b.dataset.mtab === S.mtab));
    $$('#menu .tab').forEach((s) => s.classList.toggle('active', s.dataset.mtab === S.mtab));
    if (S.mtab === 'members') renderMembers();
    else renderLogs();
}

/* ============================================================ DEV MENU */
function efFactionId() {
    return Number($('#ef-fac') && $('#ef-fac').value) || (S.dev && S.dev.faction && S.dev.faction.id) || 0;
}

function renderDevSelect() {
    const facs = (S.dev && S.dev.factions) || [];
    const cur = efFactionId();
    $('#ef-fac').innerHTML = (facs.length
        ? facs.map((f) => `<option value="${f.id}">#${f.id} ${esc(f.name)}${f.active ? '' : ' (inactive)'}</option>`).join('')
        : '<option value="">— no factions —</option>');
    if (cur) $('#ef-fac').value = String(cur);
}

function pointTag(v) { return v ? '<span class="ok">set</span>' : '<span class="no">not set</span>'; }

function renderEdit() {
    renderDevSelect();
    const f = S.dev && S.dev.faction;
    $('#ef-body').classList.toggle('hidden', !f);
    if (!f) return;

    // vehicles (all categories, each row removable)
    const cats = ['car', 'heli', 'boat'];
    let rows = '';
    cats.forEach((cat) => {
        ((f.vehicles && f.vehicles[cat]) || []).forEach((v) => {
            rows += `<div class="vrow">
                <span class="grow"><span class="lb">${esc(v.label)}</span><span class="md"> — ${esc(v.model)}</span>
                    <span class="cat">${cat}</span></span>
                <input type="number" min="1" max="7" value="${v.minRank || 1}" data-vr="${v.id}" title="min rank" />
                <button class="btn mini danger" data-vd="${v.id}">&times;</button>
            </div>`;
        });
    });
    $('#ef-vehicles').innerHTML = rows || '<div class="muted">No vehicles.</div>';
    $$('#ef-vehicles [data-vd]').forEach((b) => b.onclick = () => {
        if (confirm('Remove this vehicle?')) dop({ op: 'removeVehicle', vehId: Number(b.dataset.vd) });
    });
    $$('#ef-vehicles [data-vr]').forEach((i) => i.onchange = () =>
        dop({ op: 'setVehicleRank', vehId: Number(i.dataset.vr), minRank: Number(i.value) || 1 }));

    // points
    $('#ef-points').innerHTML =
        `HQ exterior ${pointTag(f.hqEnter)} &nbsp;·&nbsp; HQ interior ${pointTag(f.hqExit)}` +
        `${f.hqExit ? ` (vw ${f.hqVw || 0})` : ''} &nbsp;·&nbsp; ` +
        `Car ${pointTag(f.vgarage)} &nbsp;·&nbsp; Heli ${pointTag(f.hgarage)} &nbsp;·&nbsp; Boat ${pointTag(f.bgarage)}`;

    // ranks
    const rc = S.dev.rankCount || 7;
    const rcl = S.dev.rankCoLeader || 6;
    let rh = '';
    for (let i = 1; i <= rc; i++) {
        const tag = i === rc ? ' (Leader)' : i === rcl ? ' (Co-Leader)' : '';
        rh += `<label class="fld">Rank ${i}${tag}
            <input data-ri="${i}" maxlength="32" value="${esc((f.ranks || [])[i - 1] || ('Rank ' + i))}" /></label>`;
    }
    $('#ef-ranks').innerHTML = rh;

    $('#ef-leader').value = '';
    $('#ef-manager').value = '';
    $('#ef-seedrank').value = S.dev.seedDefaultRank || 3;
}

function renderDev() {
    $$('#devmenu .tabs button').forEach((b) => b.classList.toggle('active', b.dataset.dtab === S.dtab));
    $$('#devmenu .tab').forEach((s) => s.classList.toggle('active', s.dataset.dtab === S.dtab));
    if (S.dtab === 'edit') renderEdit();
}

/* ============================================================ static wiring: faction menu */
$('#close').onclick = () => post('close').then(hideAll);
$('#mem-search').addEventListener('input', (e) => { S.memSearch = e.target.value; renderMembers(); });
$$('#menu .tabs button').forEach((b) => b.onclick = () => { S.mtab = b.dataset.mtab; renderMenu(); });

/* ============================================================ static wiring: dev menu */
$('#dev-close').onclick = () => post('close').then(hideAll);
$$('#devmenu .tabs button').forEach((b) => b.onclick = () => { S.dtab = b.dataset.dtab; renderDev(); });

$('#cf-go').onclick = () => {
    const name = $('#cf-name').value.trim();
    if (name.length < 3) return;
    dop({ op: 'createFaction', name, short: $('#cf-short').value.trim() });
    $('#cf-name').value = ''; $('#cf-short').value = '';
};

$('#ef-fac').onchange = () => dop({ op: 'select', factionId: Number($('#ef-fac').value) });

$$('#devmenu .vcat').forEach((b) => b.onclick = () => {
    S.efcat = b.dataset.cat;
    $$('#devmenu .vcat').forEach((x) => x.classList.toggle('active', x === b));
});
$('#av-go').onclick = () => {
    const model = $('#av-model').value.trim();
    if (model.length < 2) return;
    dop({
        op: 'addVehicle', category: S.efcat, model,
        label: $('#av-label').value.trim() || model, minRank: Number($('#av-rank').value) || 1,
    });
    $('#av-model').value = ''; $('#av-label').value = '';
};

$$('#devmenu .dev-points button').forEach((b) => b.onclick = () =>
    dop({ op: 'setPoint', what: b.dataset.point }));

$('#ef-ranks-save').onclick = () => {
    $$('#ef-ranks input').forEach((i) =>
        dop({ op: 'setRankName', index: Number(i.dataset.ri), name: i.value.trim() }));
};
$('#ef-setleader').onclick = () => {
    const v = Number($('#ef-leader').value);
    if (v) dop({ op: 'setLeader', userId: v });
};
$('#ef-setmanager').onclick = () => {
    const v = Number($('#ef-manager').value);
    if (v) dop({ op: 'setManager', userId: v });
};
$('#ef-seed').onclick = () => dop({ op: 'seedVanilla', minRank: Number($('#ef-seedrank').value) || 3 });
$('#ef-delete').onclick = () => {
    if (confirm('Permanently DELETE this faction and remove all its members?')) dop({ op: 'deleteFaction' });
};

/* ============================================================ garage (unchanged) */
$('#g-close').onclick = () => post('close').then(() => $('#garage').classList.add('hidden'));
function renderGarage(d) {
    $('#g-title').textContent = ({ car: 'Car Garage', heli: 'Helipad', boat: 'Boat Dock' })[d.category] || 'Garage';
    $('#g-list').innerHTML = (d.list || []).map((v) => `
        <div class="grow-veh" data-id="${v.id}">
            <span>${esc(v.label)} <span class="md">(${esc(v.model)})</span></span>
            <span class="md">rank ${v.minRank || 1}+</span>
        </div>`).join('') || '<div class="muted">No vehicles available for your rank.</div>';
    $$('#g-list [data-id]').forEach((el) => el.onclick = () => {
        post('garagePick', { id: Number(el.dataset.id) });
        $('#garage').classList.add('hidden');
    });
}

/* ============================================================ show / hide */
function hideAll() {
    $('#menu').classList.add('hidden');
    $('#devmenu').classList.add('hidden');
    $('#garage').classList.add('hidden');
}

window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'openMember') {
        S.data = d.data;
        $('#devmenu').classList.add('hidden');
        $('#menu').classList.remove('hidden');
        renderMenu();
    } else if (d.action === 'memberData') {
        S.data = d.data;
        renderMenu();
    } else if (d.action === 'openDev') {
        S.dev = d.data;
        $('#menu').classList.add('hidden');
        $('#devmenu').classList.remove('hidden');
        renderDev();
    } else if (d.action === 'devData') {
        S.dev = d.data;
        renderDev();
    } else if (d.action === 'garage') {
        renderGarage(d.data || {});
        $('#garage').classList.remove('hidden');
    } else if (d.action === 'forceClose') {
        hideAll();
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('#garage').classList.contains('hidden')) { post('close'); $('#garage').classList.add('hidden'); return; }
    if (!$('#menu').classList.contains('hidden') || !$('#devmenu').classList.contains('hidden')) {
        post('close').then(hideAll);
    }
});
