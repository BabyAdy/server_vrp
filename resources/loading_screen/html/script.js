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

    // ── INTRO YOUTUBE ──────────────────────────────────
    youtubeId: '',        // <-- ID-ul clipului de YouTube (ex: din youtu.be/XXXXXXXXXXX -> 'XXXXXXXXXXX')
    introVolume: 0.35,    // 0.0 - 1.0  (volumul implicit al clipului)
    introStart: 0,        // secunda de start in clip (optional)
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

/* ── intro: YouTube IFrame Player API ────────────────────
   Video integrat de pe YouTube (fara .mp4 local). autoplay=1, controls=0,
   fundal fullscreen loop. Butonul + slider-ul de mai jos controleaza
   player.mute() / player.unMute() / player.setVolume(x). */
const muteBtn  = $('#muteBtn');
const audioCtl = $('#audioCtl');
const volSlider = $('#volSlider');

const clamp01 = (n) => Math.max(0, Math.min(100, n));   // 0..100
let vol = clamp01(Math.round((CFG.introVolume || 0.35) * 100));
let muted = false;
try {
    const sv = localStorage.getItem('ph_ls_vol');
    if (sv !== null) vol = clamp01(parseInt(sv, 10) || 0);
    muted = localStorage.getItem('ph_ls_muted') === '1';
} catch (e) {}

const ICO_ON  = 'M11 5 6 9H2v6h4l5 4V5z M15.5 8.5a5 5 0 0 1 0 7 M19 5a10 10 0 0 1 0 14';
const ICO_LOW = 'M11 5 6 9H2v6h4l5 4V5z M15.5 8.5a5 5 0 0 1 0 7';
const ICO_OFF = 'M11 5 6 9H2v6h4l5 4V5z M23 9l-6 6 M17 9l6 6';

let player = null;
let ytReady = false;

function paintAudioUI() {
    const eff = muted ? 0 : vol;
    volSlider.value = vol;
    volSlider.style.setProperty('--fill', vol + '%');
    muteBtn.classList.toggle('muted', eff === 0);
    audioCtl.classList.toggle('muted', eff === 0);
    const ico = document.getElementById('mIco');
    if (ico) ico.setAttribute('d', eff === 0 ? ICO_OFF : (eff < 45 ? ICO_LOW : ICO_ON));
    try {
        localStorage.setItem('ph_ls_vol', String(vol));
        localStorage.setItem('ph_ls_muted', muted ? '1' : '0');
    } catch (e) {}
}

// aplica volumul / mute pe playerul YouTube (scara YT e 0..100, la fel ca `vol`)
function applyAudio() {
    paintAudioUI();
    if (!player || !ytReady || typeof player.setVolume !== 'function') return;
    const eff = muted ? 0 : vol;
    try {
        if (eff === 0) {
            player.mute();
        } else {
            player.unMute();
            player.setVolume(eff);
        }
    } catch (e) {}
}

// (re)porneste redarea
function kickPlay() {
    if (!player || !ytReady || typeof player.playVideo !== 'function') return;
    try {
        const st = player.getPlayerState ? player.getPlayerState() : -1;
        if (st !== 1 /* PLAYING */ && st !== 3 /* BUFFERING */) player.playVideo();
    } catch (e) {}
}

paintAudioUI();

/* callback global cerut de iframe_api */
window.onYouTubeIframeAPIReady = function () {
    const id = String(CFG.youtubeId || '').trim();
    if (!id) {
        const s = document.getElementById('status');
        if (s) s.textContent = 'Seteaza CFG.youtubeId in script.js';
        return;
    }
    player = new YT.Player('ytPlayer', {
        width: '100%',
        height: '100%',
        videoId: id,
        playerVars: {
            autoplay: 1,
            mute: 1,              // necesar pentru autoplay; dezmutam din onReady / buton
            controls: 0,         // fara controalele YouTube
            loop: 1,
            playlist: id,        // loop pentru un singur clip
            playsinline: 1,
            start: parseInt(CFG.introStart, 10) || 0,
            modestbranding: 1,
            rel: 0,
            fs: 0,
            disablekb: 1,
            iv_load_policy: 3,
            cc_load_policy: 0,
            showinfo: 0,
        },
        events: {
            onReady: function (e) {
                ytReady = true;
                try { e.target.playVideo(); } catch (er) {}
                // cerinta 3: incearca sunetul conform setarilor; daca NUI blocheaza
                // autoplay-ul cu sunet, ramane mut pana la butonul de volum.
                applyAudio();
                setTimeout(applyAudio, 400);
                setTimeout(applyAudio, 1500);
            },
            onStateChange: function (e) {
                if (e.data === YT.PlayerState.ENDED) { try { e.target.playVideo(); } catch (er) {} }
                else if (e.data === YT.PlayerState.PLAYING) applyAudio();
                else if (e.data === YT.PlayerState.PAUSED || e.data === YT.PlayerState.CUED) kickPlay();
            },
            onError: function () {
                const s = document.getElementById('status');
                if (s) s.textContent = 'YouTube: nu s-a putut incarca clipul';
            },
        },
    });
};

// incarca API-ul DUPA ce am definit callback-ul de mai sus
(function loadYT() {
    if (window.YT && window.YT.Player) { window.onYouTubeIframeAPIReady(); return; }
    const t = document.createElement('script');
    t.src = 'https://www.youtube.com/iframe_api';
    t.async = true;
    t.onerror = function () {
        const s = document.getElementById('status');
        if (s) s.textContent = 'YouTube API: fara conexiune';
    };
    (document.head || document.body).appendChild(t);
})();

/* ── butonul de volum / mute (interfata proprie) ── */
muteBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    muted = !muted;
    if (!muted && vol === 0) vol = 25;        // unmute din 0 -> volum implicit discret
    applyAudio();                             // -> player.unMute() / player.setVolume()
    kickPlay();
});

volSlider.addEventListener('input', (e) => {
    e.stopPropagation();
    vol = clamp01(parseInt(volSlider.value, 10) || 0);
    muted = false;                            // slider-ul preia de la butonul de mute
    applyAudio();
    kickPlay();
});
volSlider.addEventListener('click', (e) => e.stopPropagation());

/* orice interactiune a userului -> incearca play + aplica sunetul dorit
   (cerinta 3: reactivare la prima actiune / la butonul de volum) */
['click', 'keydown', 'pointerdown'].forEach((ev) =>
    window.addEventListener(ev, () => { kickPlay(); applyAudio(); }));

// insista in primele ~12s (autoplay-ul YT poate intarzia)
let _pt = 0;
const _pi = setInterval(() => {
    kickPlay();
    if (ytReady && !muted && vol > 0) {
        try { if (player.isMuted && player.isMuted()) { player.unMute(); player.setVolume(vol); } } catch (e) {}
    }
    if (++_pt > 60) clearInterval(_pi);
}, 200);

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
    kickPlay();
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
