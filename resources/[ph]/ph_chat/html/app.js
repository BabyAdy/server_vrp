/* ph_chat / html / app.js */

const RES = 'ph_chat';
function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

const chat = document.getElementById('chat');
const messagesEl = document.getElementById('messages');
const inputbar = document.getElementById('inputbar');
const input = document.getElementById('input');
const promptEl = document.getElementById('prompt');
const sugEl = document.getElementById('suggestions');

const state = {
    open: false,
    cfg: { maxMessages: 47, visibleLines: 17, fadeDelay: 18000, timestamps: true },
    suggestions: [],
    history: [],
    histIdx: -1,
    lastActivity: Date.now(),
    sugActive: 0,
};

/* GTA ^0..^9 color codes */
const GTA_COLORS = {
    '0': '#ffffff', '1': '#ff6b6b', '2': '#7be07a', '3': '#ffe066',
    '4': '#6ba9ff', '5': '#6be0e0', '6': '#c98bff', '7': '#ffffff',
    '8': '#ff8f4d', '9': '#9a93b8',
};

function esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    })[c]);
}

/* text cu ^n -> html cu span-uri colorate */
function colorize(text, baseColor) {
    const parts = String(text).split(/(\^\d)/g);
    let cur = baseColor || '#e8e6f0';
    let html = '';
    for (const p of parts) {
        const m = /^\^(\d)$/.exec(p);
        if (m) { cur = GTA_COLORS[m[1]] || baseColor || '#e8e6f0'; continue; }
        if (p === '') continue;
        html += `<span style="color:${cur}">${esc(p)}</span>`;
    }
    return html;
}

function gameStamp() {
    // ora reala a clientului ca fallback; ph_hud/ph-core pot trimite stamp explicit
    const d = new Date();
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}

function addMessage(data) {
    data = data || {};
    const line = document.createElement('div');
    line.className = 'line' + (data.prefix ? '' : ' system');

    let html = '';
    if (state.cfg.timestamps) {
        html += `<span class="stamp">${esc(data.stamp || gameStamp())}</span>`;
    }
    if (data.prefix) {
        const pc = data.prefixColor || '#b98cff';
        html += `<span class="prefix" style="color:${pc}">${esc(data.prefix)}</span>`;
    }
    html += colorize(data.text || '', data.textColor);
    line.innerHTML = html;

    const atBottom =
        messagesEl.scrollHeight - messagesEl.scrollTop - messagesEl.clientHeight < 40;

    messagesEl.appendChild(line);
    while (messagesEl.children.length > state.cfg.maxMessages) {
        messagesEl.removeChild(messagesEl.firstChild);
    }

    // cand e deschis si esti scrollat in sus, nu te trage jos automat
    if (!state.open || atBottom) {
        messagesEl.scrollTop = messagesEl.scrollHeight;
    }

    state.lastActivity = Date.now();
    chat.classList.remove('faded');
}

/* ---------------------------------------------------- suggestions */
function currentToken() {
    const v = input.value;
    if (v[0] !== '/') return null;
    return v.split(' ')[0];         // "/tow"
}

function renderSuggestions() {
    const tok = currentToken();
    if (!state.open || !tok || tok.length < 1) {
        sugEl.classList.add('hidden');
        sugEl.innerHTML = '';
        return;
    }
    const matches = state.suggestions
        .filter((s) => s.name.toLowerCase().startsWith(tok.toLowerCase()))
        .slice(0, 6);

    if (matches.length === 0) {
        sugEl.classList.add('hidden');
        sugEl.innerHTML = '';
        return;
    }
    if (state.sugActive >= matches.length) state.sugActive = 0;

    sugEl.innerHTML = matches.map((s, i) => {
        const params = (s.params || []).map((p) => `[${esc(p.name || p)}]`).join(' ');
        return `<div class="sug ${i === state.sugActive ? 'active' : ''}">
            <span class="name">${esc(s.name)}</span>
            <span class="help">${esc(s.help || '')}</span>
            <span class="params">${params}</span>
        </div>`;
    }).join('');
    sugEl.classList.remove('hidden');
    sugEl._matches = matches;
}

function acceptSuggestion() {
    const matches = sugEl._matches;
    if (!matches || !matches.length) return;
    input.value = matches[state.sugActive].name + ' ';
    renderSuggestions();
}

/* ---------------------------------------------------- open / close */
function openChat(prefill) {
    state.open = true;
    state.histIdx = -1;
    chat.classList.add('open');
    chat.classList.remove('faded');
    inputbar.classList.remove('hidden');
    input.value = prefill || '';
    updatePrompt();
    renderSuggestions();
    messagesEl.scrollTop = messagesEl.scrollHeight;
    setTimeout(() => input.focus(), 10);
}

function closeChat(send) {
    const msg = send ? input.value : '';
    state.open = false;
    chat.classList.remove('open');
    inputbar.classList.add('hidden');
    sugEl.classList.add('hidden');
    input.value = '';
    input.blur();
    state.lastActivity = Date.now();
    post('close', { message: msg });
}

function updatePrompt() {
    promptEl.textContent = input.value.startsWith('/') ? 'CMD' : 'SAY';
}

/* ---------------------------------------------------- input events */
input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        e.preventDefault();
        const v = input.value.trim();
        if (v) { state.history.unshift(v); state.history = state.history.slice(0, 50); }
        closeChat(true);
    } else if (e.key === 'Escape') {
        e.preventDefault();
        closeChat(false);
    } else if (e.key === 'Tab') {
        e.preventDefault();
        acceptSuggestion();
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (sugEl._matches && !sugEl.classList.contains('hidden')) {
            state.sugActive = Math.max(0, state.sugActive - 1);
            renderSuggestions();
        } else if (state.history.length) {
            state.histIdx = Math.min(state.history.length - 1, state.histIdx + 1);
            input.value = state.history[state.histIdx] || '';
        }
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (sugEl._matches && !sugEl.classList.contains('hidden')) {
            state.sugActive = Math.min((sugEl._matches.length - 1), state.sugActive + 1);
            renderSuggestions();
        } else if (state.history.length) {
            state.histIdx = Math.max(-1, state.histIdx - 1);
            input.value = state.histIdx === -1 ? '' : state.history[state.histIdx];
        }
    }
});

input.addEventListener('input', () => {
    state.sugActive = 0;
    state.lastActivity = Date.now();
    updatePrompt();
    renderSuggestions();
});

window.addEventListener('keydown', (e) => {
    if (!state.open) return;
    if (e.key === 'PageUp') messagesEl.scrollTop -= 80;
    else if (e.key === 'PageDown') messagesEl.scrollTop += 80;
});

/* ---------------------------------------------------- fade loop */
setInterval(() => {
    if (!state.open && Date.now() - state.lastActivity > state.cfg.fadeDelay) {
        chat.classList.add('faded');
    }
}, 1000);

/* ---------------------------------------------------- client -> NUI */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    switch (d.type) {
        case 'config':
            Object.assign(state.cfg, d.data || {});
            messagesEl.style.setProperty('--vis-lines', String(state.cfg.visibleLines || 17));
            break;
        case 'message':
            addMessage(d.data);
            break;
        case 'suggestions':
            state.suggestions = d.data || [];
            if (state.open) renderSuggestions();
            break;
        case 'clear':
            messagesEl.innerHTML = '';
            break;
        case 'open':
            openChat(d.prefill || '');
            break;
    }
});

document.addEventListener('DOMContentLoaded', () => post('ready'));
