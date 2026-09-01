/* ph_hud / html / app.js */

const $ = (id) => document.getElementById(id);

function money(n) {
    return '$' + Number(n || 0).toLocaleString('en-US');
}

function fmt(sec) {
    sec = Math.max(0, sec | 0);
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    const mm = String(m).padStart(2, '0');
    const ss = String(s).padStart(2, '0');
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

function setBar(key, v) {
    v = Math.max(0, Math.min(100, Math.round(v || 0)));
    $(key).style.width = v + '%';
    $(key + 'v').textContent = v + '%';
}

function renderStatuses(list) {
    const box = $('statuses');
    box.innerHTML = '';
    (list || []).forEach((s) => {
        const el = document.createElement('div');
        el.className = 'status';
        let extra = '';
        if (s.remain != null) extra = `<b>${fmt(s.remain)}</b>`;
        else if (s.value != null) extra = `<b>${String(s.value)}</b>`;
        el.innerHTML = String(s.label || '') + extra;
        box.appendChild(el);
    });
}

function updateVeh(v) {
    const box = $('veh');
    if (!v) { box.classList.add('hidden'); return; }
    box.classList.remove('hidden');

    $('v-kmh').textContent = v.kmh ?? 0;
    $('v-gear').textContent = v.gear ?? 'N';
    $('v-rpm').style.width = Math.round((v.rpm || 0) * 100) + '%';

    $('v-fuel').textContent = (v.fuel ?? 0) + '%';
    $('c-fuel').classList.toggle('bad', (v.fuel ?? 100) <= 20);

    $('c-eng').classList.toggle('on', !!v.engine);

    const lg = $('c-lights');
    lg.classList.remove('on', 'hi');
    if (v.lights === 2) lg.classList.add('hi');
    else if (v.lights === 1) lg.classList.add('on');

    $('c-belt').classList.toggle('on', !!v.belt);
    $('c-belt').classList.toggle('bad', !v.belt);

    const lock = $('c-lock');
    const odo = $('v-odo');
    if (v.personal) {
        lock.style.display = '';
        odo.style.display = '';
        $('v-lock').textContent = v.locked ? 'LOCKED' : 'UNLOCKED';
        lock.classList.toggle('on', !!v.locked);
        odo.querySelector('b').textContent = Number(v.odoKm ?? 0).toFixed(1);
        $('v-plate').textContent = v.plate || '';
    } else {
        lock.style.display = 'none';
        odo.style.display = 'none';
    }
}

window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    switch (d.type) {
        case 'show':
            $('hud').classList.remove('hidden');
            break;
        case 'hide':
            $('hud').classList.add('hidden');
            break;
        case 'static':
            $('pid').textContent = d.id ?? 0;
            $('pname').textContent = d.name ?? '-';
            $('online').textContent = d.online ?? 0;
            $('server').textContent = d.server ?? 'PURPLE HAVOC';
            $('cash').textContent = money(d.money);
            $('bank').textContent = money(d.bank);
            break;
        case 'tick':
            setBar('hp', d.hp);
            setBar('ar', d.armor);
            setBar('hu', d.hunger);
            setBar('th', d.thirst);
            $('time').textContent = d.time || '00:00';
            $('date').textContent = d.date || '-';
            $('paycheck').textContent = d.paycheck || '00:00';
            $('mic').classList.toggle('on', !!d.talking);
            renderStatuses(d.statuses);
            updateVeh(d.veh);
            break;
    }
});
