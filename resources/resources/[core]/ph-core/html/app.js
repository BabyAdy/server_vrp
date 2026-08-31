/* ph-core / html / app.js */

const APP_JS_VERSION = 'auth-3-email';
console.log('[ph-core] app.js loaded:', APP_JS_VERSION);

const RES = 'ph-core';

function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

/* ---------------------------------------------------------- screens */
const app = document.getElementById('app');
const screens = {};
document.querySelectorAll('.screen').forEach((s) => {
    screens[s.id.replace('screen-', '')] = s;
});

let currentScreen = 'loading';

function showScreen(name) {
    if (!screens[name]) return;
    currentScreen = name;
    app.classList.add('visible');
    Object.values(screens).forEach((s) => s.classList.remove('active'));
    screens[name].classList.add('active');
    clearMessages();
    const firstInput = screens[name].querySelector('input, select');
    if (firstInput) setTimeout(() => firstInput.focus(), 30);
}

function hideUI() {
    app.classList.remove('visible');
    Object.values(screens).forEach((s) => s.classList.remove('active'));
}

/* ---------------------------------------------------------- messages */
function clearMessages() {
    document.querySelectorAll('.form-msg').forEach((m) => {
        m.textContent = '';
        m.className = 'form-msg';
    });
}

function setMsg(id, text, ok) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'form-msg' + (text ? (ok ? ' ok' : ' err') : '');
}

function setFormEnabled(formId, on) {
    const f = document.getElementById(formId);
    if (!f) return;
    f.querySelectorAll('button, input, select').forEach((el) => {
        el.disabled = !on;
    });
}

/* ---------------------------------------------------------- login */
document.getElementById('form-login').addEventListener('submit', (e) => {
    e.preventDefault();
    const fd = new FormData(e.target);
    setFormEnabled('form-login', false);
    setMsg('msg-login', 'Se verifica...', true);
    post('login', {
        username: (fd.get('username') || '').trim(),
        password: fd.get('password') || '',
    });
});

/* ---------------------------------------------------------- register */
document.getElementById('form-register').addEventListener('submit', (e) => {
    e.preventDefault();
    const fd = new FormData(e.target);
    const email = (fd.get('email') || '').trim();
    const pw = fd.get('password') || '';
    const pw2 = fd.get('password2') || '';

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
        setMsg('msg-register', 'Adresa de email invalida.', false);
        return;
    }
    if (pw !== pw2) {
        setMsg('msg-register', 'Parolele nu coincid.', false);
        return;
    }

    const payload = {
        username: (fd.get('username') || '').trim(),
        email: email,
        password: pw,
    };
    console.log('[ph-core] sending register:', JSON.stringify({ ...payload, password: '***' }));

    setFormEnabled('form-register', false);
    setMsg('msg-register', 'Se creeaza contul...', true);
    post('register', payload);
});

/* ---------------------------------------------------------- character create */
const heightInput = document.querySelector('#form-char input[name="height"]');
const heightVal = document.getElementById('height-val');
if (heightInput) {
    heightInput.addEventListener('input', () => {
        heightVal.textContent = heightInput.value;
    });
}

const dobInput = document.querySelector('#form-char input[name="dob"]');
if (dobInput) {
    dobInput.max = new Date().toISOString().slice(0, 10);
}

document.getElementById('form-char').addEventListener('submit', (e) => {
    e.preventDefault();
    const fd = new FormData(e.target);

    if (!fd.get('dob')) {
        setMsg('msg-char', 'Alege data nasterii.', false);
        return;
    }

    setFormEnabled('form-char', false);
    setMsg('msg-char', 'Se creeaza personajul...', true);
    post('createCharacter', {
        dob: fd.get('dob'),
        gender: fd.get('gender'),
        height: fd.get('height'),
    });
});

/* ---------------------------------------------------------- switch links */
document.querySelectorAll('[data-screen]').forEach((el) => {
    el.addEventListener('click', () => showScreen(el.dataset.screen));
});

/* ---------------------------------------------------------- client -> NUI */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};

    switch (d.action) {
        case 'show':
            showScreen(d.screen);
            break;

        case 'hide':
            hideUI();
            break;

        case 'authResult': {
            const r = d.data || {};
            setFormEnabled('form-login', true);
            setFormEnabled('form-register', true);
            const target = currentScreen === 'register' ? 'msg-register' : 'msg-login';
            setMsg(target, r.message, !!r.ok);
            if (r.username) {
                const nameEl = document.getElementById('cc-name');
                if (nameEl) nameEl.textContent = r.username;
            }
            break;
        }

        case 'characterResult': {
            const r = d.data || {};
            setFormEnabled('form-char', true);
            setMsg('msg-char', r.message, !!r.ok);
            break;
        }
    }
});

/* ---------------------------------------------------------- boot */
window.addEventListener('DOMContentLoaded', () => {
    post('uiReady');
});
