/* ph_appearance / html / app.js  -  character creator + /editcharacter editor */
const RES = 'ph_appearance';
function post(n, d = {}) {
    return fetch(`https://${RES}/${n}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(d),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));
}
const $ = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));
const el = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

const S = { mode: 'create', ap: null, maxes: {}, tab: 'heritage', targetName: '', template: null };

const OVL_COLOR  = { beard: 1, eyebrows: 1, makeup: 2, blush: 2, lipstick: 2 };
const OVL_FEMALE = { makeup: 1, blush: 1, lipstick: 1 };
const OVL_LABEL  = {
    eyebrows: 'Eyebrows', beard: 'Facial hair', ageing: 'Ageing', complexion: 'Complexion',
    sundamage: 'Sun damage', blemishes: 'Blemishes', moles: 'Moles & freckles',
    makeup: 'Makeup', blush: 'Blush', lipstick: 'Lipstick',
};
const FACE_GROUPS = [
    { h: 'Nose',        items: [[0, 'Width'], [1, 'Peak height'], [2, 'Peak length'], [3, 'Bone height'], [4, 'Peak lowering'], [5, 'Twist']] },
    { h: 'Brow & eyes', items: [[6, 'Brow height'], [7, 'Brow depth'], [11, 'Eye opening']] },
    { h: 'Cheeks',      items: [[8, 'Bone height'], [9, 'Bone width'], [10, 'Puffiness']] },
    { h: 'Lips & jaw',  items: [[12, 'Lip thickness'], [13, 'Jaw width'], [14, 'Jaw length']] },
    { h: 'Chin',        items: [[15, 'Lowering'], [16, 'Length'], [17, 'Pointiness'], [18, 'Hole']] },
    { h: 'Neck',        items: [[19, 'Thickness']] },
];

function tabList() {
    const t = [['heritage', 'Heritage'], ['face', 'Face'], ['hair', 'Hair'],
        ['brows', 'Brows'], ['beard', 'Beard'], ['eyes', 'Eyes'], ['skin', 'Skin']];
    if (S.ap && S.ap.gender === 1) t.push(['makeup', 'Makeup']);
    return t;
}

/* --------------------------------------------------- palettes */
function hairPalette(i) {
    if (i < 8) return `hsl(28 35% ${5 + i * 3}%)`;
    if (i < 20) return `hsl(30 55% ${16 + (i - 8) * 4}%)`;
    if (i < 28) return `hsl(45 65% ${44 + (i - 20) * 4}%)`;
    if (i < 34) return `hsl(0 0% ${52 + (i - 28) * 7}%)`;
    return `hsl(${(i * 47) % 360} 60% 55%)`;
}
function makeupPalette(i) { return `hsl(${(i * 37) % 360} 45% ${34 + (i % 5) * 8}%)`; }

/* --------------------------------------------------- controls */
function ctlSlider(label, min, max, step, val, disp, on) {
    const c = el('div', 'ctl');
    c.innerHTML = `<div class="row"><label>${label}</label><span class="val"></span></div>
        <input type="range" min="${min}" max="${max}" step="${step}" value="${val}">`;
    const out = c.querySelector('.val'), inp = c.querySelector('input');
    const upd = () => { out.textContent = disp(parseFloat(inp.value)); };
    inp.addEventListener('input', () => { upd(); on(parseFloat(inp.value)); });
    upd();
    return c;
}
function ctlStepper(label, min, max, val, disp, on) {
    const c = el('div', 'ctl');
    c.innerHTML = `<div class="row"><label>${label}</label></div>
        <div class="stepper"><button data-d="-1">&lsaquo;</button><span class="sv"></span><button data-d="1">&rsaquo;</button></div>`;
    const sv = c.querySelector('.sv');
    let v = val;
    const render = () => { sv.textContent = disp(v); };
    c.querySelectorAll('button').forEach((b) => b.onclick = () => {
        v = clamp(v + Number(b.dataset.d), min, max);
        render(); on(v);
    });
    render();
    return c;
}
function ctlSwatch(label, count, val, palette, on) {
    const c = el('div', 'ctl');
    c.innerHTML = `<div class="row"><label>${label}</label><span class="val">#${val}</span></div><div class="swatches"></div>`;
    const wrap = c.querySelector('.swatches'), out = c.querySelector('.val');
    for (let i = 0; i < count; i++) {
        const b = el('button');
        b.style.background = palette(i);
        if (i === val) b.classList.add('sel');
        b.onclick = () => {
            wrap.querySelectorAll('button').forEach((x) => x.classList.remove('sel'));
            b.classList.add('sel'); out.textContent = '#' + i; on(i);
        };
        wrap.append(b);
    }
    return c;
}

/* --------------------------------------------------- state updates */
function up(section, key, value) {
    if (section === 'heritage') S.ap.heritage[key] = value;
    else if (section === 'face') S.ap.face[key] = value;
    else if (section === 'hair') S.ap.hair[key] = value;
    else if (section === 'eyeColor') S.ap.eyeColor = value;
    post('paUpdate', { section, key, index: key, value });
}
function upOverlay(key, sub, value) {
    S.ap.overlays[key][sub] = value;
    post('paUpdate', { section: 'overlay', key, sub, value });
    if (sub === 'style') renderContent();
}

/* --------------------------------------------------- tab renderers */
function grp(title) { const g = el('div', 'grp'); g.append(el('h4', null, title)); return g; }

function tabHeritage() {
    const g = grp('Parents & blend');
    const m = S.maxes.heritageParent || 45;
    g.append(ctlStepper('Mother', 0, m, S.ap.heritage.mom, (v) => 'Face ' + v, (v) => up('heritage', 'mom', v)));
    g.append(ctlStepper('Father', 0, m, S.ap.heritage.dad, (v) => 'Face ' + v, (v) => up('heritage', 'dad', v)));
    g.append(ctlSlider('Resemblance (mother ↔ father)', 0, 100, 1, Math.round(S.ap.heritage.shapeMix * 100),
        (v) => Math.round(v) + '%', (v) => up('heritage', 'shapeMix', v / 100)));
    g.append(ctlSlider('Skin tone (mother ↔ father)', 0, 100, 1, Math.round(S.ap.heritage.skinMix * 100),
        (v) => Math.round(v) + '%', (v) => up('heritage', 'skinMix', v / 100)));
    return [g];
}
function tabFace() {
    return FACE_GROUPS.map((G) => {
        const g = grp(G.h);
        G.items.forEach(([id, name]) => {
            g.append(ctlSlider(name, -100, 100, 1, Math.round((S.ap.face[id] || 0) * 100),
                (v) => Math.round(v), (v) => up('face', id, v / 100)));
        });
        return g;
    });
}
function tabHair() {
    const g = grp('Hair');
    g.append(ctlStepper('Style', 0, S.maxes.hair || 0, S.ap.hair.style, (v) => String(v), (v) => up('hair', 'style', v)));
    g.append(ctlSwatch('Colour', (S.maxes.hairColor || 63) + 1, S.ap.hair.color, hairPalette, (v) => up('hair', 'color', v)));
    g.append(ctlSwatch('Highlight', (S.maxes.hairColor || 63) + 1, S.ap.hair.highlight, hairPalette, (v) => up('hair', 'highlight', v)));
    return [g];
}
function overlayControls(key, palette) {
    const g = grp(OVL_LABEL[key] || key);
    const o = S.ap.overlays[key];
    const max = (S.maxes.overlays && S.maxes.overlays[key]) || 0;
    g.append(ctlStepper('Style', -1, max, o.style, (v) => (v < 0 ? 'None' : String(v)), (v) => upOverlay(key, 'style', v)));
    if (o.style >= 0) {
        g.append(ctlSlider('Opacity', 0, 100, 1, Math.round((o.opacity ?? 1) * 100),
            (v) => Math.round(v) + '%', (v) => upOverlay(key, 'opacity', v / 100)));
        if (palette) {
            const cnt = (palette === makeupPalette ? (S.maxes.makeupColor || 63) : (S.maxes.hairColor || 63)) + 1;
            g.append(ctlSwatch('Colour', cnt, o.color || 0, palette, (v) => upOverlay(key, 'color', v)));
        }
    }
    return g;
}
function tabBrows() { return [overlayControls('eyebrows', hairPalette)]; }
function tabBeard() { return [overlayControls('beard', hairPalette)]; }
function tabEyes() {
    const g = grp('Eyes');
    g.append(ctlSwatch('Eye colour', (S.maxes.eyeColor || 30) + 1, S.ap.eyeColor, (i) => `hsl(${(i * 26) % 360} 45% 42%)`,
        (v) => up('eyeColor', null, v)));
    return [g];
}
function tabSkin() {
    return ['ageing', 'complexion', 'sundamage', 'blemishes', 'moles'].map((k) => overlayControls(k, null));
}
function tabMakeup() {
    return ['makeup', 'blush', 'lipstick'].map((k) => overlayControls(k, makeupPalette));
}

const TAB_FN = {
    heritage: tabHeritage, face: tabFace, hair: tabHair, brows: tabBrows,
    beard: tabBeard, eyes: tabEyes, skin: tabSkin, makeup: tabMakeup,
};

/* --------------------------------------------------- render */
function renderTabs() {
    const tabs = tabList();
    if (!tabs.find((t) => t[0] === S.tab)) S.tab = 'heritage';
    $('#tabs').innerHTML = tabs.map((t) =>
        `<button data-tab="${t[0]}" class="${t[0] === S.tab ? 'active' : ''}">${t[1]}</button>`).join('');
    $$('#tabs button').forEach((b) => b.onclick = () => { S.tab = b.dataset.tab; renderTabs(); renderContent(); });
}
function renderContent() {
    const c = $('#content');
    c.innerHTML = '';
    (TAB_FN[S.tab] || tabHeritage)().forEach((node) => c.append(node));
}
function renderGender() {
    $$('#gender button').forEach((b) => b.classList.toggle('active', Number(b.dataset.g) === (S.ap.gender || 0)));
}
function renderFoot() {
    const f = $('#foot');
    if (S.mode === 'create') {
        f.innerHTML = `<button class="btn go" id="done">Enter game</button>`;
        $('#done').onclick = () => { post('paCreateDone', { appearance: S.ap }); hideRoot(); };
    } else {
        f.innerHTML = `<button class="btn alt" id="save">Save</button>
            <button class="btn go" id="savetpl">Save Character</button>
            <button class="btn sm ghost" id="close">Close</button>`;
        $('#save').onclick = () => post('paEditorSave', { appearance: S.ap });
        $('#savetpl').onclick = () => post('paEditorTemplate', { appearance: S.ap });
        $('#close').onclick = () => { post('paClose'); hideRoot(); };
    }
}
function renderBanner() {
    const b = $('#tpl-banner');
    if (S.mode === 'editor' && S.template) {
        b.classList.remove('hidden');
        $('#tpl-text').textContent = `Saved ${(S.ap.gender === 1) ? 'female' : 'male'} template available.`;
    } else {
        b.classList.add('hidden');
    }
}
function renderAll() {
    $('#hd-title').textContent = S.mode === 'editor' ? 'Edit Character' : 'Character Creator';
    $('#hd-sub').textContent = S.mode === 'editor' ? `#${S.targetId ?? '?'} ${S.targetName || ''}` : 'Design your look — clothing is set for you';
    renderGender(); renderBanner(); renderTabs(); renderContent(); renderFoot();
}

/* --------------------------------------------------- static wiring */
$$('#gender button').forEach((b) => b.onclick = () => {
    const g = Number(b.dataset.g);
    if (!S.ap || g === S.ap.gender) return;
    post('paUpdate', { section: 'gender', value: g });
});
$$('.cam-row button').forEach((b) => b.onclick = () => post('paCam', { focus: b.dataset.focus }));
$('#tpl-load').onclick = () => { if (S.template) post('paLoadTemplate', { appearance: S.template }); };
$('#tpl-skip').onclick = () => { S.template = null; renderBanner(); };

/* stage drag / zoom */
(() => {
    const stage = $('#stage');
    let dragging = false, lx = 0, ly = 0;
    stage.addEventListener('mousedown', (e) => { dragging = true; lx = e.clientX; ly = e.clientY; stage.classList.add('drag'); });
    window.addEventListener('mouseup', () => { dragging = false; stage.classList.remove('drag'); });
    window.addEventListener('mousemove', (e) => {
        if (!dragging) return;
        const dh = e.clientX - lx, dp = e.clientY - ly;
        lx = e.clientX; ly = e.clientY;
        post('paCam', { dh, dp });
    });
    stage.addEventListener('wheel', (e) => { post('paCam', { dz: -e.deltaY / 120 }); });
})();

/* --------------------------------------------------- show / hide */
function showRoot() { $('#root').classList.remove('hidden'); }
function hideRoot() { $('#root').classList.add('hidden'); }

window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'open') {
        const x = d.data || {};
        S.mode = x.mode || 'create';
        S.ap = x.appearance;
        S.maxes = x.maxes || {};
        S.targetId = x.targetId;
        S.targetName = x.targetName || '';
        S.template = x.template || null;
        S.tab = 'heritage';
        renderAll();
        showRoot();
    } else if (d.action === 'genderSwitched') {
        const x = d.data || {};
        S.ap = x.appearance;
        S.maxes = x.maxes || S.maxes;
        S.template = x.template || null;
        renderAll();
    } else if (d.action === 'setAll') {
        const x = d.data || {};
        S.ap = x.appearance;
        S.maxes = x.maxes || S.maxes;
        S.template = null;
        renderAll();
    } else if (d.action === 'close') {
        hideRoot();
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && S.mode === 'editor') { post('paClose'); hideRoot(); }
});
