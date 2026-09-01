/* ph_shop / html / app.js */

const $ = (s) => document.querySelector(s);
const RES = 'ph_shop';
let FORM = null;   // { which, cost, ... }

function post(name, data) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

function card(it) {
    const el = document.createElement('div');
    el.className = 'card';
    let btn;
    if (it.locked) {
        btn = `<button class="btn" disabled>${it.lockMsg || 'Unavailable'}</button>`;
    } else if (!it.afford) {
        btn = `<button class="btn" disabled>Need ${it.cost} PP</button>`;
    } else {
        btn = `<button class="btn go" data-key="${it.key}">${it.kind === 'form' ? 'Continue' : 'Buy'}</button>`;
    }
    el.innerHTML = `
        <div class="cl">${it.label}</div>
        <div class="cd">${it.desc || ''}</div>
        <div class="crow"><span class="cc">${it.cost} PP</span>${btn}</div>`;
    const b = el.querySelector('button[data-key]');
    if (b) b.addEventListener('click', () => post('buy', { key: b.dataset.key }));
    return el;
}

function render(d) {
    $('#pp').textContent = `${d.pp ?? 0} PP`;
    const list = $('#list');
    list.innerHTML = '';
    (d.items || []).forEach((it) => list.appendChild(card(it)));
}

function openForm(d) {
    FORM = d;
    $('#form').classList.remove('hidden');
    $('#f-err').textContent = '';
    $('#f-a').value = '';
    $('#f-b').value = '';
    $('#f-cost').textContent = `Cost: ${d.cost} PP (charged on confirm)`;

    if (d.which === 'phone') {
        $('#f-title').textContent = 'Choose your phone number';
        $('#f-label-a').textContent = `Number (${d.phoneMin}-${d.phoneMax}, A-Z 0-9)`;
        $('#f-a').maxLength = d.phoneMax;
        $('#f-row-b').classList.add('hidden');
    } else {
        $('#f-title').textContent = 'Create a clan';
        $('#f-label-a').textContent = `Clan name (max ${d.nameMax})`;
        $('#f-a').maxLength = d.nameMax;
        $('#f-label-b').textContent = `Clan tag (max ${d.tagMax})`;
        $('#f-b').maxLength = d.tagMax;
        $('#f-row-b').classList.remove('hidden');
    }
    setTimeout(() => $('#f-a').focus(), 30);
}

function closeForm() {
    FORM = null;
    $('#form').classList.add('hidden');
}

function submitForm() {
    if (!FORM) return;
    if (FORM.which === 'phone') {
        const v = $('#f-a').value.trim().toUpperCase();
        if (v.length < FORM.phoneMin) { $('#f-err').textContent = `At least ${FORM.phoneMin} characters.`; return; }
        post('phoneSet', { value: v });
    } else {
        const name = $('#f-a').value.trim();
        const tag = $('#f-b').value.trim();
        if (name.length < 3) { $('#f-err').textContent = 'Name too short (min 3).'; return; }
        if (tag.length < 1) { $('#f-err').textContent = 'Tag is required.'; return; }
        post('clanRequest', { name, tag });
    }
}

function close() {
    closeForm();
    $('#wrap').classList.add('hidden');
}

window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.action === 'open') {
        $('#wrap').classList.remove('hidden');
        closeForm();
        render(m.data || {});
    } else if (m.action === 'form') {
        openForm(m.data || {});
    } else if (m.action === 'formError') {
        $('#f-err').textContent = (m.data && m.data.msg) || 'Error.';
    } else if (m.action === 'formDone') {
        closeForm();
    } else if (m.action === 'forceClose') {
        close();
    }
});

$('#close').addEventListener('click', () => { close(); post('close'); });
$('#f-x').addEventListener('click', closeForm);
$('#f-cancel').addEventListener('click', closeForm);
$('#f-ok').addEventListener('click', submitForm);
document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') {
        if (FORM) { closeForm(); return; }
        if (!$('#wrap').classList.contains('hidden')) { close(); post('close'); }
    }
    if (e.key === 'Enter' && FORM) submitForm();
});
