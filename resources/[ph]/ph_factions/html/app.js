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

const S = { data: null, mtab: 'members', dev: null, dtab: 'create', efcat: 'car' };

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
const prettyAction = (a) => String(a || '').replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

/* ============================================================ FACTION MENU */
const BADGE_CLASS = {
    leader: 'leader-badge', coleader: 'co-leader-badge',
    supervisor: 'supervisor-badge', tester: 'tester-badge',
};

/* one <span class="badge"> for a Config.Badges key */
function badgeChip(key) {
    const b = (S.data && S.data.badges && S.data.badges[key]) || { label: key, color: '#b98cff', icon: '' };
    const cls = BADGE_CLASS[key] || '';
    return `<span class="badge ${cls}" style="color:${esc(b.color)}">${esc(b.icon || '')} ${esc(b.label)}</span>`;
}

/* full badge set for a member (rank badge + supervisor + tester, like the template) */
function memberBadges(m) {
    const rl = S.data.rankLeader || 7;
    const rc = S.data.rankCoLeader || 6;
    const out = [];
    if (m.rank >= rl) out.push(badgeChip('leader'));
    else if (m.rank >= rc) out.push(badgeChip('coleader'));
    if (m.supervisor) out.push(badgeChip('supervisor'));
    if (m.tester) out.push(badgeChip('tester'));
    return out.length ? `<div class="badges-wrapper">${out.join('')}</div>` : '<span class="none-badge">-</span>';
}

/* buttons for the "Manage" column, gated the same way the server gates the op */
function memberActions(m) {
    const role = S.data.role || {};
    const rl = S.data.rankLeader || 7;
    const isSelf = m.id === role.me;
    const myRank = role.rank || 0;
    const out = [];

    const d = `data-u="${m.id}" data-n="${esc(m.name)}"`;
    if (role.isLeader && !isSelf && m.rank < rl) {
        out.push(`<button class="btn btn-rank" data-a="setRank" ${d} title="Change Rank"><i class="fa-solid fa-angles-up"></i> Rank</button>`);
    }
    if (role.canManage && !isSelf && m.rank < myRank) {
        out.push(`<button class="btn btn-warn" data-a="warn" ${d} title="Give Faction Warn"><i class="fa-solid fa-triangle-exclamation"></i> FW</button>`);
    }
    if (role.canManage && m.warns > 0) {
        out.push(`<button class="btn btn-unwarn" data-a="unwarn" ${d} title="Remove Warn"><i class="fa-solid fa-shield-halved"></i> Unwarn</button>`);
    }
    if (role.canManage && !isSelf && m.rank < myRank) {
        out.push(`<button class="btn btn-uninvite" data-a="uninvite" ${d} title="Uninvite"><i class="fa-solid fa-user-xmark"></i> Uninvite</button>`);
        out.push(`<button class="btn btn-supervisor" data-a="toggleSupervisor" ${d} title="Toggle Supervisor"><i class="fa-solid fa-user-shield"></i> ${m.supervisor ? 'Remove Sup' : 'Supervisor'}</button>`);
        out.push(`<button class="btn btn-tester" data-a="toggleTester" ${d} title="Toggle Tester"><i class="fa-solid fa-vial"></i> ${m.tester ? 'Remove Tester' : 'Tester'}</button>`);
    }
    return out.length ? `<div class="action-buttons">${out.join('')}</div>` : '<span class="no-action">No action available</span>';
}

function renderMembers() {
    const ranks = (S.data.faction || {}).ranks || [];
    const list = S.data.members || [];
    $('#members').innerHTML = list.map((m) => {
        const rkName = ranks[m.rank - 1] || ('Rank ' + m.rank);
        const wcls = m.warns > 0 ? 'warns-count has-warns' : 'warns-count';
        const off = m.online ? '' : ' <span class="wtag off">offline</span>';
        return `<tr>
            <td><span class="table-avatar">${monogram(m.name)}</span></td>
            <td class="username">${esc(m.name)}${off}</td>
            <td>${Number(m.days || 0).toFixed(2)}</td>
            <td><span class="rank-badge rank-${m.rank}">${esc(rkName)} <span class="rn">(${m.rank})</span></span></td>
            <td><span class="${wcls}">${m.warns}/${S.data.maxWarns}</span></td>
            <td>${memberBadges(m)}</td>
            <td>${memberActions(m)}</td>
        </tr>`;
    }).join('') || '<tr><td colspan="7" class="no-action">No members.</td></tr>';

    $$('#members [data-a]').forEach((b) => b.onclick = () => {
        const a = b.dataset.a, u = Number(b.dataset.u);
        const name = b.dataset.n || ('#' + u);
        if (a === 'setRank') {
            const max = (S.data.rankLeader || 7) - 1;
            const v = parseInt(prompt(`New rank for ${name} (1-${max}):`, ''), 10);
            if (v >= 1 && v <= max) mop({ op: 'setRank', userId: u, rank: v });
        } else if (a === 'warn') {
            const reason = prompt(`Warn reason for ${name}:`) || '';
            mop({ op: 'warn', userId: u, reason });
        } else if (a === 'uninvite') {
            if (confirm(`Uninvite ${name} from the faction?`)) mop({ op: 'uninvite', userId: u });
        } else {
            mop({ op: a, userId: u });
        }
    });
}

function renderLogs() {
    const rows = S.data.logs || [];
    const empty = $('#logs-empty');
    if (!rows.length) {
        $('#logs').innerHTML = '';
        empty.classList.remove('hidden');
        return;
    }
    empty.classList.add('hidden');
    $('#logs').innerHTML = rows.map((r) => `<tr>
        <td>${esc(r.created_at || '')}</td>
        <td>${esc(r.actor_name || '—')}</td>
        <td>${esc(prettyAction(r.action))}</td>
        <td>${esc(r.target_name || '—')}</td>
        <td>${esc(r.detail || '')}</td>
    </tr>`).join('');
}

function renderMenu() {
    if (!S.data) return;
    const fac = S.data.faction || {};
    const role = S.data.role || {};

    const logo = $('#fm-logo');
    if (S.data.logo) { logo.src = S.data.logo; } else { logo.removeAttribute('src'); }
    $('#fm-server').textContent = S.data.serverName || 'Purple Havoc';
    $('#fm-fid').textContent = '[' + (fac.id != null ? fac.id : '–') + ']';
    $('#fm-fname').textContent = fac.name || '–';
    $('#fm-uname').textContent = role.myName || '–';
    $('#fm-avatar').innerHTML = monogram(role.myName || '?');

    $$('#menu .nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.mtab === S.mtab));
    $$('#menu .tab-content').forEach((s) => s.classList.toggle('active', s.id === S.mtab + '-tab'));
    if (S.mtab === 'logs') renderLogs();
    else renderMembers();
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
$$('#menu .nav-btn').forEach((b) => b.onclick = () => { S.mtab = b.dataset.mtab; renderMenu(); });

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
