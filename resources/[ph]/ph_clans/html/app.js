/* ph_clans / html / app.js
   #clan -> Clan Menu (/clan)
   Tabs: Members | Vehicles | Vehicles Management | Clan Logs | SafeBox | Information | Settings
   NUI bus: inbound  {action:'open'|'data'|'forceClose', data}
            outbound post('menu', {op,...}) , post('close') */
const RES = 'ph_clans';
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
const fmt = (n) => Number(n || 0).toLocaleString('en-US');
const prettyAction = (a) => String(a || '').replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
function monogram(name, px) {
    const s = String(name || '?');
    const ch = (s.trim()[0] || '?').toUpperCase();
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    const size = px ? `width:${px}px;height:${px}px;` : '';
    return `<span class="mono" style="${size}background:hsl(${Math.abs(h) % 360}deg 52% 42%)">${esc(ch)}</span>`;
}
const hex6 = (c) => (/^#[0-9a-f]{6}$/i.test(String(c)) ? String(c) : (/^#[0-9a-f]{3}$/i.test(String(c))
    ? '#' + String(c).slice(1).split('').map((x) => x + x).join('') : '#b98cff'));

const S = {
    data: null, catalog: [], ctab: 'members',
    memSearch: '', bcat: 'all', buySearch: '',
    permTarget: null, rankTarget: null,
};
const cop = (payload) => post('menu', payload);

/* ============================================================ data helpers */
function clan() { return (S.data && S.data.clan) || {}; }
function role() { return (S.data && S.data.role) || {}; }
function cfg() { return (S.data && S.data.cfg) || {}; }
function hasPerm(k) { return (role().perms || []).includes(k); }
function rankName(i) { return (clan().ranks || [])[i - 1] || ('Rank ' + i); }

const PERM_META = {
    changerank: { icon: 'fa-turn-up', label: 'Change Rank' },
    vehmgmt: { icon: 'fa-car', label: 'Vehicle Management' },
    invite: { icon: 'fa-user-plus', label: 'Invite Access' },
    kick: { icon: 'fa-user-xmark', label: 'Kick Access' },
    warn: { icon: 'fa-triangle-exclamation', label: 'Warn Access' },
};
const permMeta = (k) => PERM_META[k] || { icon: 'fa-circle', label: k };

/* ============================================================ head + tabs */
function renderHead() {
    const c = clan(), r = role();
    const logo = $('#c-logo');
    if (c.logo) logo.src = c.logo; else logo.removeAttribute('src');
    $('#c-server').textContent = c.serverName || 'Purple Havoc';
    $('#c-id').textContent = c.id != null ? c.id : '–';
    $('#c-name').textContent = c.name || '–';
    $('#c-tag').textContent = c.tag ? `[${c.tag}]` : '';
    $('#c-tag').classList.toggle('hidden', !c.tag);
    $('#c-role').textContent = r.isLeader ? 'Leader'
        : r.rank === cfg().rankCoLeader ? 'Co-Leader' : (r.rankName || ('Rank ' + r.rank));
    $('#c-inactive').classList.toggle('hidden', !!c.active);
    $('#c-me').textContent = r.myName || '–';
    $('#c-avatar').innerHTML = monogram(r.myName || '?');
    $('#nav-settings').classList.toggle('hidden', !r.canSettings);
    if (S.ctab === 'settings' && !r.canSettings) S.ctab = 'members';
}

const RENDERERS = {
    members: renderMembers, vehicles: renderVehicles, 'veh-management': renderVehManagement,
    logs: renderLogs, safebox: renderSafebox, info: renderInfo, settings: renderSettings,
};

function renderTab() {
    $$('#clan .nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.ctab === S.ctab));
    $$('#clan .tab-content').forEach((s) => s.classList.toggle('active', s.id === 'tab-' + S.ctab));
    (RENDERERS[S.ctab] || renderMembers)();
}

function renderAll() {
    if (!S.data) return;
    renderHead();
    renderTab();
}

/* ============================================================ Members */
function permIcons(m) {
    const keys = cfg().permKeys || [];
    return `<div class="perm-icons" title="${keys.map((k) => permMeta(k).label).join(' | ')}">` + keys.map((k) => {
        const on = (m.perms || []).includes(k) || (m.rank >= (cfg().rankLeader || 7));
        return `<i class="fa-solid ${permMeta(k).icon} perm-icon ${on ? 'on' : 'off'}"></i>`;
    }).join('') + `</div>`;
}

function manageCell(m) {
    const r = role();
    if (m.id === r.userId) return `<span class="no-info">You</span>`;
    const out = [];
    const lower = m.rank < r.rank;
    if (r.isLeader && m.online && m.rank < (cfg().rankLeader || 7)) {
        out.push(`<button class="btn-action btn-rank" title="Change Rank" data-a="rankModal" data-u="${m.id}"><i class="fa-solid fa-angles-up"></i></button>`);
    }
    if ((r.isLeader || hasPerm('warn')) && m.online && lower) {
        out.push(`<button class="btn-action btn-add-warn" title="Give Clan Warn" data-a="warn" data-u="${m.id}"><i class="fa-solid fa-circle-exclamation"></i></button>`);
        if (m.warns > 0) out.push(`<button class="btn-action btn-rem-warn" title="Remove Clan Warn" data-a="unwarn" data-u="${m.id}"><i class="fa-solid fa-circle-check"></i></button>`);
    }
    if ((r.isLeader || hasPerm('kick')) && lower) {
        out.push(`<button class="btn-action btn-kick" title="Kick Member" data-a="kick" data-u="${m.id}"><i class="fa-solid fa-user-minus"></i></button>`);
    }
    if (r.canManage && m.online && lower) {
        out.push(`<button class="btn-action btn-perm" title="Manage Permissions" data-a="permModal" data-u="${m.id}"><i class="fa-solid fa-sliders"></i></button>`);
    }
    return out.length ? `<div class="action-buttons">${out.join('')}</div>` : `<span class="no-info">No actions available</span>`;
}

function memberBadge(m) {
    const rl = cfg().rankLeader || 7, rc = cfg().rankCoLeader || 6;
    const col = (clan().rankColors || [])[m.rank - 1];
    if (m.rank >= rl) return `<span class="b" style="color:${hex6(col || '#eab308')}"><i class="fa-solid fa-crown"></i> Leader</span>`;
    if (m.rank >= rc) return `<span class="b" style="color:${hex6(col || '#a855f7')}"><i class="fa-solid fa-shield-halved"></i> Co-Leader</span>`;
    return `<span class="none">-</span>`;
}

function renderMembers() {
    const r = role();
    $('#invite-row').classList.toggle('hidden',
        !(r.canManage || hasPerm('invite') || r.rank >= (cfg().inviteRank || 5)));

    const q = S.memSearch.toLowerCase();
    const list = (S.data.members || []).filter((m) => !q || String(m.name).toLowerCase().includes(q));
    $('#members-body').innerHTML = list.map((m) => {
        const wc = m.warns > 0 ? 'warn-cell has' : 'warn-cell';
        const off = m.online ? '' : ' <span class="u-off">(offline)</span>';
        return `<tr>
            <td><span class="table-avatar">${monogram(m.name)}</span></td>
            <td><span class="u-name">${esc(m.name)}</span>${off}</td>
            <td>${Number(m.days || 0).toFixed(2)}</td>
            <td class="rank-cell">${esc(rankName(m.rank))} <span class="rn">(${m.rank})</span></td>
            <td class="${wc}">${m.warns}/${cfg().warnCap}</td>
            <td class="badge-cell">${memberBadge(m)}</td>
            <td>${permIcons(m)}</td>
            <td>${manageCell(m)}</td>
            <td>${m.lastLogin ? esc(String(m.lastLogin).replace('T', ' ').replace(/\..*$/, '')) : '—'}</td>
        </tr>`;
    }).join('') || `<tr><td colspan="9" class="no-info">No members.</td></tr>`;

    $$('#members-body [data-a]').forEach((b) => b.onclick = () => {
        const a = b.dataset.a, u = Number(b.dataset.u);
        if (a === 'rankModal') openRankModal(u);
        else if (a === 'permModal') openPermModal(u);
        else if (a === 'warn') cop({ op: 'warn', userId: u, reason: prompt('Warn reason (optional):') || '' });
        else if (a === 'kick') { if (confirm('Kick this member from the clan?')) cop({ op: 'kick', userId: u }); }
        else cop({ op: a, userId: u });
    });
}

/* ============================================================ Vehicles (spawn/despawn) */
const VEH_ICON = { car: 'fa-car', heli: 'fa-helicopter', boat: 'fa-ship' };

function renderVehicles() {
    const r = role();
    const list = S.data.vehicles || [];
    $('#veh-count').textContent = `${list.length} / ${cfg().vehMax} clan vehicles`
        + (r.canVehBasic ? '' : ' — you lack vehicle access');
    $('#vehicles-grid').innerHTML = list.map((v) => {
        const btn = !r.canVehBasic ? ''
            : v.live
                ? `<button class="btn-veh btn-despawn" data-a="vehDespawn" data-v="${v.id}">Despawn</button>`
                : `<button class="btn-veh btn-spawn" data-a="vehSpawn" data-v="${v.id}">Spawn</button>`;
        return `<div class="vehicle-card">
            <div class="vehicle-img-container">
                <i class="fa-solid ${VEH_ICON[v.category] || 'fa-car'} vicon"></i>
                <span class="rank-badge">${esc(String(v.category || 'car').toUpperCase())}</span>
            </div>
            <div class="vehicle-name">${esc(v.label)}</div>
            <div class="vehicle-sub">${esc(v.model)} · ${esc(v.plate)} · upg ${v.upgrade}/${cfg().upgradeMax}${v.live ? ' · spawned' : ''}</div>
            <div class="vehicle-actions">${btn}</div>
        </div>`;
    }).join('') || `<div class="placeholder-text">No clan vehicles. Buy one in "Vehicles Management".</div>`;

    wireVehButtons('#vehicles-grid');
}

/* ============================================================ Vehicles Management */
function renderVehManagement() {
    const r = role();
    const list = S.data.vehicles || [];
    $('#veh-mgmt-count').textContent = `${list.length} / ${cfg().vehMax} owned`;
    $('#open-buy-modal').disabled = !r.canVehManage;

    $('#veh-mgmt-container').innerHTML = list.map((v) => {
        const acts = [];
        if (r.canVehBasic) {
            acts.push(v.live
                ? `<button class="btn-mgmt btn-mgmt-sell" data-a="vehDespawn" data-v="${v.id}">Despawn</button>`
                : `<button class="btn-mgmt btn-mgmt-spawn" data-a="vehSpawn" data-v="${v.id}">Spawn</button>`);
        }
        if (r.canVehManage) {
            if (v.upgrade < cfg().upgradeMax) {
                acts.push(`<button class="btn-mgmt btn-mgmt-upgrade" data-a="vehUpgrade" data-v="${v.id}">Upgrade $${fmt(cfg().upgradeCost)}</button>`);
            }
            acts.push(`<button class="btn-mgmt btn-mgmt-sell" data-a="vehSell" data-v="${v.id}">Sell</button>`);
        }
        return `<div class="veh-mgmt-row">
            <div class="veh-mgmt-info">
                <div class="veh-mgmt-ic"><i class="fa-solid ${VEH_ICON[v.category] || 'fa-car'}"></i></div>
                <div class="veh-mgmt-details">
                    <span class="veh-mgmt-name">${esc(v.label)}</span>
                    <span class="veh-mgmt-id">[ID: ${v.id}] ${esc(v.model)} · ${esc(v.plate)} · upgrade ${v.upgrade}/${cfg().upgradeMax} · $${fmt(v.price)}</span>
                </div>
            </div>
            <div class="veh-mgmt-actions">${acts.join('') || '<span class="no-info">No actions</span>'}</div>
        </div>`;
    }).join('') || `<div class="placeholder-text">No clan vehicles yet. Use "Buy Clan Vehicle".</div>`;

    wireVehButtons('#veh-mgmt-container');
}

function wireVehButtons(scope) {
    $$(`${scope} [data-a]`).forEach((b) => b.onclick = () => {
        const a = b.dataset.a, v = Number(b.dataset.v);
        if (a === 'vehSell') {
            if (confirm(`Sell this vehicle? Refund is ${Math.round((cfg().sellPct || 0) * 100)}% of its price.`)) cop({ op: a, vehId: v });
        } else if (a === 'vehUpgrade') {
            if (confirm(`Upgrade this vehicle for $${fmt(cfg().upgradeCost)} from the safebox?`)) cop({ op: a, vehId: v });
        } else {
            cop({ op: a, vehId: v });
        }
    });
}

/* ============================================================ Buy modal */
function priceOf(e) {
    if (Number(e.price) > 0) return Math.floor(e.price);
    const fp = cfg().fallbackPrice || {};
    return Math.floor(fp[e.category] || fp.car || 15000);
}
function renderBuyList() {
    const q = S.buySearch.toLowerCase();
    const all = (S.catalog || []).filter((e) =>
        (S.bcat === 'all' || e.category === S.bcat) &&
        (!q || String(e.model).toLowerCase().includes(q) || String(e.label).toLowerCase().includes(q)));
    const shown = all.slice(0, 250);
    $('#shop-veh-list').innerHTML = shown.map((e) => `
        <div class="shop-veh-item">
            <div class="shop-veh-details">
                <span class="shop-veh-name">${esc(e.label)}<span class="cat">${esc(e.category)}</span></span>
                <span class="shop-veh-price">$${fmt(priceOf(e))}${e.custom ? ' · custom' : ''}</span>
            </div>
            <button class="btn-shop-buy" data-buy="${esc(e.model)}">Buy Vehicle</button>
        </div>`).join('')
        + (all.length > shown.length ? `<div class="no-info">…and ${all.length - shown.length} more — refine your search.</div>` : '')
        || `<div class="placeholder-text">No matching vehicles.</div>`;

    $$('#shop-veh-list [data-buy]').forEach((b) => b.onclick = () => {
        if (confirm(`Buy "${b.dataset.buy}" for the clan (paid from the money safebox)?`)) {
            cop({ op: 'vehBuy', model: b.dataset.buy });
            closeModal('buy-modal');
        }
    });
}

/* ============================================================ Clan Logs */
function renderLogs() {
    const rows = S.data.logs || [];
    $('#logs-empty').classList.toggle('hidden', rows.length > 0);
    $('#logs-body').innerHTML = rows.map((r) => `<tr>
        <td class="l-time">${esc(r.created_at || '')}</td>
        <td>${esc(r.actor_name || '—')}</td>
        <td class="l-action">${esc(prettyAction(r.action))}</td>
        <td>${esc(r.target_name || '—')}</td>
        <td class="l-detail">${esc(r.detail || '')}</td>
    </tr>`).join('');
}

/* ============================================================ SafeBox */
function renderSafebox() {
    const sb = clan().safebox || {};
    $('#safebox-money').textContent = '$' + fmt(sb.money);
    $('#safebox-pp').textContent = fmt(sb.pp) + ' PP';
    $('#safebox-cp').textContent = fmt(sb.clanPoints) + ' CP';
    const leader = !!role().isLeader;
    $$('#tab-safebox .wd-btn').forEach((b) => { b.disabled = !leader; });
    $('#wd-note').textContent = leader ? 'Withdraw moves funds back to your character.' : 'Withdraw is Leader only.';
}

/* ============================================================ Information */
function renderInfo() {
    const c = clan(), r = role();
    const sb = c.safebox || {};
    const rows = [
        ['Name', esc(c.name)],
        ['Tag', c.tag ? `[${esc(c.tag)}]` : '—'],
        ['Status', c.active ? `Active — ${c.daysLeft} day(s) left` : 'Inactive (0 days left)'],
        ['Members', `${c.memberCount}`],
        ['Vehicles', `${c.vehCount} / ${cfg().vehMax}`],
        ['Founder', esc(c.founderName || '—')],
        ['Leader', esc(c.leaderName || '—')],
        ['Chat colour', `<span style="color:${hex6(c.chatColor)}">${esc(c.chatColor || '—')}</span>`],
        ['Chat lock', `Rank ${c.chatLockRank || 1}+`],
        ['MOTD', esc(c.motd || '—')],
        ['Safebox', `$${fmt(sb.money)} · ${fmt(sb.pp)} PP · ${fmt(sb.clanPoints)} CP`],
    ];
    $('#info-grid').innerHTML = rows.map(([k, v]) => `<div class="k">${k}</div><div>${v}</div>`).join('');

    const acc = [
        ['Your rank', `${esc(r.rankName)} (${r.rank})`],
        ['Role', r.isLeader ? 'Leader' : r.canManage ? 'Co-Leader / Manager' : 'Member'],
        ['Permissions', (r.perms && r.perms.length) ? r.perms.map((k) => permMeta(k).label).join(', ') : (r.isLeader ? 'All (Leader)' : 'None')],
        ['Vehicle access', r.canVehManage ? 'Buy / Sell / Upgrade / Spawn' : r.canVehBasic ? 'Spawn / Despawn' : 'None'],
        ['Settings access', r.canSettings ? 'Yes' : 'No'],
    ];
    $('#info-access').innerHTML = acc.map(([k, v]) => `<div class="k">${k}</div><div>${v}</div>`).join('');
}

/* ============================================================ Settings */
function renderSettings() {
    const c = clan();
    const rc = cfg().rankCount || 7;
    const names = c.ranks || [];
    const cols = c.rankColors || [];

    let rh = '';
    for (let i = rc; i >= 1; i--) {
        const tag = i === rc ? ' (Leader)' : i === cfg().rankCoLeader ? ' (Co-Leader)' : '';
        rh += `<div class="settings-row"><div class="settings-input-group">
            <label><i class="fa-solid fa-shield"></i> Rank ${i}${tag}</label>
            <div class="settings-input-row">
                <input type="text" class="custom-input rank-name-input" data-rn="${i}" maxlength="15" value="${esc(names[i - 1] || ('Rank ' + i))}" placeholder="Rank name" />
                <input type="color" class="color-picker-input" data-rc="${i}" value="${hex6(cols[i - 1])}" />
            </div>
        </div></div>`;
    }
    $('#set-ranks').innerHTML = rh;

    $('#set-chatcolor').value = hex6(c.chatColor);
    $('#set-chatcolor-hex').value = c.chatColor || '#b98cff';
    $('#set-motd').value = c.motd || '';

    const lock = $('#set-lock');
    lock.innerHTML = '';
    for (let i = 1; i <= rc; i++) {
        lock.innerHTML += `<option value="${i}">Rank ${i}${i === rc ? ' only' : '+'}</option>`;
    }
    lock.value = String(c.chatLockRank || 1);

    const styles = cfg().tagStyles || [];
    $('#set-tag').innerHTML = styles.map((s, i) =>
        `<option value="${i + 1}">${i + 1} — ${esc(s.replace('%t', 'TAG').replace('%s', 'Name'))}</option>`).join('');
    $('#set-tag').value = String((role().tagStyle || 0) + 1);
    const prev = styles[(role().tagStyle || 0)] || '[%t] %s';
    $('#tag-preview').textContent = prev.replace('%t', c.tag || 'TAG').replace('%s', 'Name');
}

/* ============================================================ Modals */
function openModal(id) { $('#' + id).classList.add('show'); }
function closeModal(id) { $('#' + id).classList.remove('show'); }

function openRankModal(uid) {
    const m = (S.data.members || []).find((x) => x.id === uid);
    if (!m) return;
    S.rankTarget = uid;
    $('#rank-modal-user').textContent = m.name;
    const max = (cfg().rankLeader || 7) - 1;
    $('#rank-input-label').textContent = `Enter new rank (1 - ${max}):`;
    const inp = $('#rank-input');
    inp.max = String(max);
    inp.value = String(Math.min(m.rank, max));
    openModal('rank-modal');
}
$('#rank-save').onclick = () => {
    const v = parseInt($('#rank-input').value, 10);
    const max = (cfg().rankLeader || 7) - 1;
    if (S.rankTarget && v >= 1 && v <= max) {
        cop({ op: 'setRank', userId: S.rankTarget, rank: v });
        closeModal('rank-modal');
    }
};

function openPermModal(uid) {
    const m = (S.data.members || []).find((x) => x.id === uid);
    if (!m) return;
    S.permTarget = uid;
    $('#perm-modal-user').textContent = m.name;
    const keys = cfg().permKeys || [];
    $('#perm-modal-body').innerHTML = keys.map((k) => `
        <div class="perm-toggle-group">
            <span><i class="fa-solid ${permMeta(k).icon}"></i> ${esc(permMeta(k).label)}</span>
            <label class="switch"><input type="checkbox" data-pk="${k}" ${(m.perms || []).includes(k) ? 'checked' : ''}><span class="slider"></span></label>
        </div>`).join('');
    openModal('perm-modal');
}
$('#perm-save').onclick = () => {
    const uid = S.permTarget;
    const m = uid && (S.data.members || []).find((x) => x.id === uid);
    if (!m) return closeModal('perm-modal');
    $$('#perm-modal-body [data-pk]').forEach((cb) => {
        const has = (m.perms || []).includes(cb.dataset.pk);
        if (cb.checked !== has) cop({ op: 'permToggle', userId: uid, key: cb.dataset.pk });
    });
    closeModal('perm-modal');
};

/* ============================================================ static wiring */
function hide() { $('#clan').classList.add('hidden'); }
$('#c-close').onclick = () => post('close').then(hide);
$$('#clan .nav-btn').forEach((b) => b.onclick = () => { S.ctab = b.dataset.ctab; renderTab(); });
$$('#clan [data-close]').forEach((el) => el.onclick = () => closeModal(el.dataset.close));
$$('#clan .modal-overlay').forEach((ov) => ov.onclick = (e) => { if (e.target === ov) closeModal(ov.id); });

$('#mem-search').addEventListener('input', (e) => { S.memSearch = e.target.value; renderMembers(); });
$('#inv-go').onclick = () => {
    const v = Number($('#inv-id').value);
    if (v) { cop({ op: 'invite', sqlId: v }); $('#inv-id').value = ''; }
};

$('#open-buy-modal').onclick = () => { S.buySearch = ''; $('#buy-search').value = ''; renderBuyList(); openModal('buy-modal'); };
$('#buy-search').addEventListener('input', (e) => { S.buySearch = e.target.value; renderBuyList(); });
$$('#buy-cats [data-bcat]').forEach((b) => b.onclick = () => {
    S.bcat = b.dataset.bcat;
    $$('#buy-cats [data-bcat]').forEach((x) => x.classList.toggle('active', x === b));
    renderBuyList();
});

$$('#tab-safebox [data-dep]').forEach((b) => b.onclick = () => {
    const kind = b.dataset.dep;
    const amt = Number($('#dep-' + kind).value);
    if (amt > 0) { cop({ op: 'deposit', kind, amount: amt }); $('#dep-' + kind).value = ''; }
});
$$('#tab-safebox [data-wd]').forEach((b) => b.onclick = () => {
    const kind = b.dataset.wd;
    const amt = Number($('#dep-' + kind).value);
    if (amt > 0) { cop({ op: 'withdraw', kind, amount: amt }); $('#dep-' + kind).value = ''; }
});

$('#set-ranks-go').onclick = () => {
    const names = {}, colors = {};
    $$('#set-ranks [data-rn]').forEach((i) => names[i.dataset.rn] = i.value.trim());
    $$('#set-ranks [data-rc]').forEach((i) => colors[i.dataset.rc] = i.value);
    cop({ op: 'setRankNames', values: names });
    cop({ op: 'setRankColors', values: colors });
};
$('#set-chatcolor').addEventListener('input', (e) => { $('#set-chatcolor-hex').value = e.target.value; });
$('#set-chatcolor-hex').addEventListener('input', (e) => {
    if (/^#[0-9a-f]{6}$/i.test(e.target.value)) $('#set-chatcolor').value = e.target.value;
});
$('#set-chatcolor-go').onclick = () => cop({ op: 'setChatColor', value: $('#set-chatcolor-hex').value.trim() });
$('#set-motd-go').onclick = () => cop({ op: 'setMotd', value: $('#set-motd').value });
$('#set-lock-go').onclick = () => cop({ op: 'setChatLock', value: Number($('#set-lock').value) || 1 });
$('#set-tag-go').onclick = () => cop({ op: 'setTagStyle', value: Number($('#set-tag').value) || 1 });

/* ============================================================ message bus */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        S.data = d.data;
        if (d.data && Array.isArray(d.data.catalog)) S.catalog = d.data.catalog;
        $('#clan').classList.remove('hidden');
        renderAll();
    } else if (d.action === 'data') {
        S.data = d.data;
        if (d.data && Array.isArray(d.data.catalog)) S.catalog = d.data.catalog;
        renderAll();
    } else if (d.action === 'forceClose') {
        hide();
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    const openM = $$('#clan .modal-overlay.show');
    if (openM.length) { openM.forEach((m) => m.classList.remove('show')); return; }
    if (!$('#clan').classList.contains('hidden')) post('close').then(hide);
});
