(() => {
    const messagesEl = document.getElementById('messages');
    const inputWrap = document.getElementById('input-wrap');
    const input = document.getElementById('chat-input');
    const fpsEl = document.getElementById('fps');

    const MAX_MESSAGES = 30;      // buffer pastrat (vizibil prin scroll cand chat-ul e deschis)
    const FADE_AFTER_MS = 12000;  // dupa cat timp inactiv se estompeaza (cand e inchis)

    let open = false;
    let resourceName = 'chat';

    try {
        if (typeof GetParentResourceName === 'function') {
            resourceName = GetParentResourceName();
        }
    } catch (_) {}

    const isNui = typeof GetParentResourceName === 'function';

    function pad(n) {
        return String(n).padStart(2, '0');
    }

    function nowTime() {
        const d = new Date();
        return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function safeColor(c) {
        return typeof c === 'string' && /^#[0-9a-fA-F]{3,8}$/.test(c) ? c : null;
    }

    function addMessage({ time, rank, rankColor, name, id, text }) {
        const el = document.createElement('div');
        el.className = 'msg';

        const safeTime = escapeHtml(time || nowTime());
        const safeRank = escapeHtml(rank || '');
        const safeName = escapeHtml(name || 'Necunoscut');
        const safeId = escapeHtml(String(id ?? '?'));
        const safeText = escapeHtml(text || '');
        const col = safeColor(rankColor);

        const rankHtml = safeRank
            ? `<span class="rank"${col ? ` style="color:${col}"` : ''}>[${safeRank}]</span> `
            : '';

        el.innerHTML =
            `<span class="time">[${safeTime}]</span> ` +
            rankHtml +
            `<span class="name">${safeName}</span> ` +
            `<span class="id">(${safeId})</span>` +
            `<span class="sep">: </span>` +
            `<span class="text">${safeText}</span>`;

        // nu te trage la baza daca esti scrollat in sus si citesti
        const atBottom =
            messagesEl.scrollHeight - messagesEl.scrollTop - messagesEl.clientHeight < 40;

        messagesEl.appendChild(el);

        while (messagesEl.children.length > MAX_MESSAGES) {
            messagesEl.removeChild(messagesEl.firstChild);
        }

        if (!open || atBottom) {
            messagesEl.scrollTop = messagesEl.scrollHeight;
        }

        el._fadeTimer = setTimeout(() => {
            if (!open) el.classList.add('fade');
        }, FADE_AFTER_MS);
    }

    function clearFadeTimers() {
        [...messagesEl.children].forEach((el) => {
            el.classList.remove('fade');
            if (el._fadeTimer) clearTimeout(el._fadeTimer);
        });
    }

    function scheduleFadeAll() {
        [...messagesEl.children].forEach((el) => {
            el.classList.remove('fade');
            if (el._fadeTimer) clearTimeout(el._fadeTimer);
            el._fadeTimer = setTimeout(() => {
                if (!open) el.classList.add('fade');
            }, FADE_AFTER_MS);
        });
    }

    function setOpen(state) {
        open = state;
        document.body.classList.toggle('chat-open', state);
        if (open) {
            clearFadeTimers();
            inputWrap.classList.remove('hidden');
            input.value = '';
            messagesEl.scrollTop = messagesEl.scrollHeight;
            setTimeout(() => input.focus(), 20);
        } else {
            inputWrap.classList.add('hidden');
            input.blur();
            scheduleFadeAll();
        }
    }

    function post(name, data) {
        fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function sendMessage() {
        const text = input.value.trim();
        if (!text) {
            setOpen(false);
            post('close', {});
            return;
        }

        if (isNui) {
            post('send', { message: text });
        } else {
            addMessage({
                time: nowTime(),
                rank: 'Fondator',
                name: 'kent',
                id: 2,
                text,
            });
        }

        input.value = '';
        setOpen(false);
        if (isNui) post('close', {});
    }

    window.addEventListener('message', (event) => {
        const data = event.data || {};

        if (data.action === 'open') {
            setOpen(true);
        } else if (data.action === 'close') {
            setOpen(false);
        } else if (data.action === 'message') {
            addMessage(data);
        } else if (data.action === 'fps') {
            fpsEl.textContent = data.fps != null ? `${data.fps}fps` : '';
        } else if (data.action === 'clear') {
            messagesEl.innerHTML = '';
        }
    });

    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            sendMessage();
        } else if (e.key === 'Escape') {
            e.preventDefault();
            setOpen(false);
            post('close', {});
        }
    });

    // FPS overlay
    let frames = 0;
    let last = performance.now();
    function tick(now) {
        frames++;
        if (now - last >= 1000) {
            fpsEl.textContent = `${frames}fps`;
            frames = 0;
            last = now;
        }
        requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);

    // Preview mode (browser)
    if (!isNui) {
        document.body.classList.add('preview');
        addMessage({
            time: '15:12',
            rank: 'Fondator',
            name: 'CarlosZVR',
            id: 1,
            text: 'ASASDGADGA',
        });
        addMessage({
            time: '15:12',
            rank: 'Fondator',
            name: 'kent',
            id: 2,
            text: 'ttttt',
        });
        setOpen(true);

        window.addEventListener('keydown', (e) => {
            if (e.key === 't' || e.key === 'T') {
                if (document.activeElement === input) return;
                e.preventDefault();
                setOpen(true);
            }
        });
    }
})();
