/* ph_vehicles / html / app.js  -  garajul personal (/v) */

const $ = (s) => document.querySelector(s);
const RES = 'ph_vehicles';
let IMG = 'img/';

function post(name, data) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

const IC = {
    fuel: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 20V6a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v14M3 20h12M14 9h2.5A1.5 1.5 0 0 1 18 10.5V17a2 2 0 0 0 4 0V8l-3-3"/></svg>',
    odo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM12 12l4-3M4.9 19a9 9 0 1 1 14.2 0"/></svg>',
    plate: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="3" y="7" width="18" height="10" rx="2"/><path d="M7 11h2m3 0h5M7 14h10"/></svg>',
    spawn: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
    last: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7M3 4v4h4"/></svg>',
    locate: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21s7-6.3 7-11a7 7 0 1 0-14 0c0 4.7 7 11 7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>',
    despawn: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M6 7h12M9 7V5h6v2m-7 0 1 12h6l1-12"/></svg>',
    unstuck: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18"/></svg>',
};

function card(v) {
    const el = document.createElement('div');
    el.className = 'card';
    const stateCls = v.spawned ? 'out' : 'stored';
    const stateTxt = v.spawned ? 'Out' : 'Stored';

    let acts = '';
    if (v.spawned) {
        acts = `
            <button class="btn" data-op="locate" data-id="${v.id}">${IC.locate}Locate</button>
            <button class="btn danger" data-op="despawn" data-id="${v.id}">${IC.despawn}Despawn</button>
            <button class="btn" data-op="unstuck" data-id="${v.id}">${IC.unstuck}Unstuck</button>`;
    } else {
        const pd = v.hasPark ? '' : 'disabled title="Set a park spot with /park first"';
        const ld = v.hasLast ? '' : 'disabled title="No stored last location"';
        acts = `
            <button class="btn go" data-op="spawn" data-id="${v.id}" ${pd}>${IC.spawn}Spawn</button>
            <button class="btn" data-op="spawnLast" data-id="${v.id}" ${ld}>${IC.last}Last Location</button>`;
    }

    el.innerHTML = `
        <div class="pic" style="background-image:url('${IMG}${v.model}.png')">
            <span class="state ${stateCls}">${stateTxt}</span>
            <span class="name">${v.label || v.model}</span>
        </div>
        <div class="meta">
            <span class="mi">${IC.plate}<b>${v.plate || '-'}</b></span>
            <span class="mi">${IC.odo}<b>${(v.odoKm ?? 0).toFixed(1)} km</b></span>
            <span class="mi">${IC.fuel}<b>${v.fuel ?? 100}%</b></span>
        </div>
        <div class="acts">${acts}</div>`;

    const pic = el.querySelector('.pic');
    const probe = new Image();
    probe.onerror = () => { pic.style.backgroundImage = `url('${IMG}_default.png')`; };
    probe.src = `${IMG}${v.model}.png`;

    el.querySelectorAll('button[data-op]').forEach((b) => {
        b.addEventListener('click', () => {
            if (b.hasAttribute('disabled')) return;
            post('vAction', { op: b.dataset.op, id: Number(b.dataset.id) });
        });
    });
    return el;
}

function render(d) {
    if (d.imgDir) IMG = d.imgDir;
    $('#slots').textContent = `${d.used ?? 0} / ${d.slots ?? 0} slots`;
    const list = $('#list');
    list.innerHTML = '';
    const arr = d.list || [];
    if (!arr.length) {
        list.innerHTML = '<div class="empty">You do not own any personal vehicles yet.</div>';
        return;
    }
    arr.forEach((v) => list.appendChild(card(v)));
}

function open(d) { $('#wrap').classList.remove('hidden'); render(d); }
function close() { $('#wrap').classList.add('hidden'); }

window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.action === 'open') open(m.data || {});
    else if (m.action === 'refresh') { if (!$('#wrap').classList.contains('hidden')) render(m.data || {}); }
    else if (m.action === 'forceClose') close();
});

$('#close').addEventListener('click', () => { close(); post('close'); });
document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape' && !$('#wrap').classList.contains('hidden')) { close(); post('close'); }
});
