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
            break;
    }
});
