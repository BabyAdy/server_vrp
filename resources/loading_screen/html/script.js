/* ============ Purple Havoc · loading screen ============ */

/* ── edit me ─────────────────────────────────────────── */
const CFG = {
    community: 'Purple Havoc',
    tagline: 'Community',
    discord: 'discord.gg/purple-havoc',
    ucp: 'ucp.puple-havoc.ro',
    staff: [
        ['Owner', 'BabyAdy'],
        ['Developer', 'BabyAdy'],
        ['Manager', 'BabyAdy'],
    ],
    credit: 'Developed by: BabyAdy',
    introVolume: 0.35, // 0.0 - 1.0  (volumul implicit al clipului introv2.mp4)
};
/* ────────────────────────────────────────────────────── */

const $ = (s) => document.querySelector(s);

// apply config text
try {
    $('.brand-txt h1').textContent = CFG.community;
    $('.brand-txt span').textContent = CFG.tagline;
    document.querySelectorAll('.link .v')[0].textContent = CFG.discord;
    document.querySelectorAll('.link .v')[1].textContent = CFG.ucp;
    $('.l-credit').textContent = CFG.credit;
    const staffBox = $('#staff');
    staffBox.innerHTML = CFG.staff.map(([k, v], i) =>
        `<div class="st-row" style="animation-delay:${0.15 + i * 0.1}s"><span class="st-k">${k}</span><span class="st-v">${v}</span></div>`
    ).join('');
} catch (e) { /* ignore */ }

/* ── intro clip audio (mute toggle + volume level) ────────
   Sunetul vine DIRECT din introv2.mp4 (nu mai exista .mp3 separat,
   care se desincroniza). Butonul + slider-ul regleaza volumul clipului. */
const video = $('#bgVideo');
const muteBtn = $('#muteBtn');
const audioCtl = $('#audioCtl');
const volSlider = $('#volSlider');

video.removeAttribute('controls');
video.loop = true;
video.playsInline = true;

const clamp01 = (n) => Math.max(0, Math.min(100, n));
let vol = clamp01(Math.round((CFG.introVolume || 0.35) * 100));
let muted = false;
try {
    const sv = localStorage.getItem('ph_ls_vol');
    if (sv !== null) vol = clamp01(parseInt(sv, 10) || 0);
    muted = localStorage.getItem('ph_ls_muted') === '1';
} catch (e) {}

const ICO_ON = 'M11 5 6 9H2v6h4l5 4V5z M15.5 8.5a5 5 0 0 1 0 7 M19 5a10 10 0 0 1 0 14';
const ICO_LOW = 'M11 5 6 9H2v6h4l5 4V5z M15.5 8.5a5 5 0 0 1 0 7';
const ICO_OFF = 'M11 5 6 9H2v6h4l5 4V5z M23 9l-6 6 M17 9l6 6';

function applyAudio() {
    const effective = muted ? 0 : vol;
    video.volume = effective / 100;
    video.muted = effective === 0;

    volSlider.value = vol;
    volSlider.style.setProperty('--fill', vol + '%');
    muteBtn.classList.toggle('muted', effective === 0);
    audioCtl.classList.toggle('muted', effective === 0);

    const ico = document.getElementById('mIco');
    if (ico) ico.setAttribute('d', effective === 0 ? ICO_OFF : (effective < 45 ? ICO_LOW : ICO_ON));

    try {
        localStorage.setItem('ph_ls_vol', String(vol));
        localStorage.setItem('ph_ls_muted', muted ? '1' : '0');
    } catch (e) {}
}
applyAudio();

function tryPlay() {
    const p = video.play();
    if (p && p.catch) {
        p.catch(() => {
            // ultima varianta: daca redarea cu sunet e blocata, ruleaza macar mut
            const wasMuted = video.muted;
            video.muted = true;
            const p2 = video.play();
            if (p2 && p2.then) p2.then(() => { if (!wasMuted && !muted) { video.muted = false; applyAudio(); } }).catch(() => {});
        });
    }
}
tryPlay();
window.addEventListener('click', tryPlay, { once: false });
window.addEventListener('keydown', tryPlay, { once: false });
video.addEventListener('canplay', tryPlay, { once: true });
video.addEventListener('loadeddata', tryPlay, { once: true });

muteBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    muted = !muted;
    if (!muted && vol === 0) vol = 25; // unmuting from 0 -> a quiet default
    applyAudio();
    if (!muted) tryPlay();
});

volSlider.addEventListener('input', (e) => {
    e.stopPropagation();
    vol = clamp01(parseInt(volSlider.value, 10) || 0);
    muted = false; // moving the slider always takes over from the mute toggle
    applyAudio();
    tryPlay();
});
volSlider.addEventListener('click', (e) => e.stopPropagation());

/* ── progress ────────────────────────────────────────────────────────────
   FiveM sends progress in several phases. `loadProgress` finishes early
   (mount / first data), then data-file entries, then the long resource
   startup (`initFunctionInvoking`). We blend them with weights so the bar
   fills gradually and only reaches 100% when resources are actually up —
   matching the % the game shows bottom-right.                            */
const bar = $('#bar');
const pctEl = $('#pct');
const statusEl = $('#status');

const W = { load: 0.08, data: 0.20, init: 0.72 }; // must sum to 1
const phase = { load: 0, data: 0, init: 0 };
let dataCount = 0, initCount = 0;
let initStarted = false;
let shown = 0;

function paint(pct) {
    pct = Math.max(0, Math.min(100, pct));
    if (pct <= shown) return;      // never go backwards
    shown = pct;
    bar.style.width = pct + '%';
    pctEl.textContent = Math.round(pct) + '%';
}
function recompute() {
    paint((phase.load * W.load + phase.data * W.data + phase.init * W.init) * 100);
}

window.addEventListener('message', (e) => {
    const d = e.data || {};
    switch (d.eventName) {
        case 'loadProgress':
            phase.load = Math.max(phase.load, d.loadFraction || 0);
            statusEl.textContent = 'The session is being prepared...';
            recompute();
            break;

        case 'startDataFileEntries':
            dataCount = d.count || 0;
            statusEl.textContent = 'Loading data files...';
            break;
        case 'onDataFileEntry':
        case 'performMappedDataFileEntries':
            if (d.count) dataCount = d.count;
            if (dataCount > 0 && d.idx != null) phase.data = Math.max(phase.data, (d.idx + 1) / dataCount);
            recompute();
            break;

        case 'startInitFunctionOrder':
        case 'startInitFunction':
            if (d.count) initCount = Math.max(initCount, d.count);
            initStarted = true;
            statusEl.textContent = 'Starting resources...';
            break;
        case 'initFunctionInvoking':
            if (d.count) initCount = Math.max(initCount, d.count);
            if (initCount > 0 && d.idx != null) phase.init = Math.max(phase.init, (d.idx + 1) / initCount);
            if (d.name) statusEl.textContent = 'Resource: ' + d.name;
            recompute();
            break;
        case 'initFunctionInvoked':
            if (initCount > 0 && d.idx != null) phase.init = Math.max(phase.init, (d.idx + 1) / initCount);
            recompute();
            break;

        case 'onLogLine':
            if (d.message && d.message.length < 64) statusEl.textContent = d.message;
            break;
    }
    tryPlay();
});

// keep the bar alive: tiny creep at the very start, and a slow creep through the
// resource-startup phase in case per-resource events are sparse on this build
setInterval(() => {
    if (!initStarted && shown < 4) { paint(shown + 0.25); return; }
    if (initStarted && phase.init < 0.97) { phase.init = Math.min(0.97, phase.init + 0.004); recompute(); }
}, 120);

// browser preview only (in-game the NUI host is cfx-nui-*)
if (!location.hostname.startsWith('cfx-nui-')) {
    let p = 0;
    const id = setInterval(() => { p = Math.min(100, p + Math.random() * 3.5); paint(p); if (p >= 100) clearInterval(id); }, 300);
}
