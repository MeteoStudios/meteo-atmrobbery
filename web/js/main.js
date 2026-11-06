

const RING_R = 47;
const RING_GAP = 8;
const RING_START = -90;
const END_HOLD_MS = 450;
const LOW_TIME = 0.25;
const SVG_NS = 'http://www.w3.org/2000/svg';

const CHECK_SVG =
    '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const CROSS_SVG =
    '<svg viewBox="0 0 24 24"><path d="M7 7l10 10M17 7L7 17" fill="none" stroke="currentColor" stroke-width="3.6" stroke-linecap="round"/></svg>';

const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'meteo-atmrobbery';

function post(event, data) {
    return $.post(`https://${resourceName}/${event}`, JSON.stringify(data || {}));
}

function createSound(src, poolSize, volume) {
    const pool = [];
    for (let i = 0; i < poolSize; i++) {
        const audio = new Audio(src);
        audio.volume = volume;
        pool.push(audio);
    }
    let index = 0;
    return {
        play() {
            const audio = pool[index];
            index = (index + 1) % pool.length;
            audio.currentTime = 0;
            audio.play().catch(() => {});
        },
    };
}

const sounds = {
    tap: createSound('sounds/tap.wav', 4, 0.2),
    complete: createSound('sounds/complete.wav', 1, 0.4),
    failed: createSound('sounds/failed.mp3', 1, 0.4),
};

const damp = (cur, tgt, k, dt) => cur + (tgt - cur) * (1 - Math.exp(-k * dt));
const clamp01 = (v) => Math.max(0, Math.min(1, v));

function polar(deg) {
    const r = (deg * Math.PI) / 180;
    return [66 + RING_R * Math.cos(r), 66 + RING_R * Math.sin(r)];
}

function arcPath(a0, a1) {
    const p0 = polar(a0);
    const p1 = polar(a1);
    return `M${p0[0].toFixed(2)} ${p0[1].toFixed(2)} A${RING_R} ${RING_R} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${p1[0].toFixed(2)} ${p1[1].toFixed(2)}`;
}

function restartClass(el, cls) {
    el.classList.remove(cls);
    void el.offsetWidth;
    el.classList.add(cls);
}

function normalizeKey(raw) {
    let key = String(raw || 'E').toUpperCase();
    if (key === ' ' || key === 'SPACE') key = ' ';
    return { key, label: key === ' ' ? 'SPC' : key };
}

function ringPath(d, cls) {
    const path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('d', d);
    path.setAttribute('class', cls);
    path.setAttribute('pathLength', '100');
    path.style.strokeDasharray = '100';
    return path;
}

function buildDom(steps) {
    const root = document.createElement('div');
    root.className = 'mg-keymash';
    root.innerHTML =
        '<div class="widget"><div class="inner">' +
        '<svg class="ring" viewBox="0 0 132 132"></svg>' +
        '<div class="disc"><div class="lyr base"><div class="key"></div></div>' +
        '<div class="lyr fill"><div class="key"></div></div></div>' +
        '</div></div>';

    const ring = root.querySelector('.ring');
    const span = 360 / steps.length;
    const len = span - RING_GAP;
    const segments = steps.map((_, i) => {
        const a0 = RING_START + i * span + RING_GAP / 2;
        const d = arcPath(a0, a0 + len);
        const track = ringPath(d, 'trk');
        const fill = ringPath(d, 'segf');
        track.style.strokeDashoffset = '0';
        fill.style.strokeDashoffset = '100';
        ring.append(track, fill);
        return { track, fill, shown: 0, cur: 0 };
    });

    document.body.appendChild(root);
    return {
        root,
        inner: root.querySelector('.inner'),
        disc: root.querySelector('.disc'),
        fillEl: root.querySelector('.lyr.fill'),
        labels: Array.from(root.querySelectorAll('.key')),
        segments,
    };
}

let game = null;

function startKeymash(id, config) {
    if (game) game.destroy();

    const steps = (config.keys && config.keys.length ? config.keys : ['E']).map(normalizeKey);
    const presses = config.presses || 10;
    const drain = config.drain || 3;
    const time = config.time || 0;

    const { root, inner, disc, fillEl, labels, segments } = buildDom(steps);

    const timers = [];
    const later = (fn, ms) => timers.push(setTimeout(fn, ms));

    let index = 0;
    let target = 0;
    let current = 0;
    let left = 1;
    let locked = false;
    let finished = false;
    let resultSent = false;
    let stepStart = performance.now();
    let frame = 0;
    let running = true;
    let lastTime = performance.now();

    const setKey = (step) => {
        for (const el of labels) {
            el.textContent = step.label;
            el.classList.toggle('sm', step.label.length > 1);
        }
    };

    const swapKey = (step) => {
        for (const el of labels) el.classList.add('swap');
        later(() => {
            setKey(step);
            for (const el of labels) el.classList.remove('swap');
        }, 120);
    };

    const setIcon = (svg) => {
        for (const el of labels) {
            el.innerHTML = svg;
            el.classList.remove('sm');
        }
    };

    const jolt = (px) => {
        const a = Math.random() * Math.PI * 2;
        inner.style.setProperty('--jx', `${(Math.cos(a) * px).toFixed(2)}px`);
        inner.style.setProperty('--jy', `${(Math.sin(a) * px).toFixed(2)}px`);
        restartClass(inner, 'jolt');
    };

    const stopLoop = () => {
        running = false;
        cancelAnimationFrame(frame);
        document.removeEventListener('keydown', onKeyDown);
    };

    const destroy = () => {
        stopLoop();
        for (const t of timers) clearTimeout(t);
        root.remove();
        if (game && game.id === id) game = null;
    };

    const sendResult = (success, close) => {
        if (resultSent) return;
        resultSent = true;
        post('finish', { id, success });
        stopLoop();
        if (close) return destroy();
        root.classList.remove('on');
        root.classList.add('out');
        later(destroy, END_HOLD_MS);
    };

    const succeed = () => {
        locked = true;
        finished = true;
        target = 1;
        current = 1;
        fillEl.classList.remove('warn');
        fillEl.classList.add('ok');
        setIcon(CHECK_SVG);
        sounds.complete.play();
        later(() => sendResult(true), END_HOLD_MS);
    };

    const fail = () => {
        locked = true;
        finished = true;
        target = 1;
        current = 1;
        fillEl.classList.remove('warn');
        fillEl.classList.add('red');
        setIcon(CROSS_SVG);
        restartClass(disc, 'shake');
        jolt(4);
        sounds.failed.play();
        later(() => sendResult(false), END_HOLD_MS);
    };

    const stepDone = () => {
        locked = true;
        target = 1;
        segments[index].shown = 1;
        segments[index].track.classList.remove('low');
        fillEl.classList.remove('warn');

        const last = index === steps.length - 1;
        later(() => {
            if (finished) return;
            if (last) return succeed();
            index++;
            target = 0;
            current = 0;
            left = 1;
            stepStart = performance.now();
            swapKey(steps[index]);
            locked = false;
        }, 250);
    };

    const press = () => {
        target = Math.min(1, target + 1 / presses);
        restartClass(disc, 'nudge');
        jolt(2);
        sounds.tap.play();
        if (target >= 1) stepDone();
    };

    function onKeyDown(e) {
        if (e.key === 'Escape') {
            if (!resultSent) sendResult(false, true);
            return;
        }
        if (e.repeat || locked) return;

        if (e.key.length > 1 && e.key !== ' ') return;
        const got = e.key === ' ' ? ' ' : e.key.toUpperCase();
        if (got !== steps[index].key) {
            restartClass(disc, 'shake');
            return;
        }
        press();
    }

    const update = (dt, now) => {
        if (!locked) {

            if (target > 0) target = Math.max(0, target - dt / drain);

            if (time) {
                left = clamp01(1 - (now - stepStart) / (time * 1000));
                const low = left < LOW_TIME;
                segments[index].track.classList.toggle('low', low);
                fillEl.classList.toggle('warn', low);
                if (left <= 0) return fail();
            }
        }

        current = damp(current, target, 22, dt);
        fillEl.style.clipPath = `inset(${(100 - current * 100).toFixed(2)}% 0 0 0)`;

        for (let i = 0; i < segments.length; i++) {
            const seg = segments[i];
            seg.cur = damp(seg.cur, seg.shown, 16, dt);
            seg.fill.style.strokeDashoffset = (100 - seg.cur * 100).toFixed(2);
            seg.track.style.strokeDashoffset = i === index ? (100 - left * 100).toFixed(2) : '0';
        }
    };

    const animate = () => {
        if (!running) return;
        const now = performance.now();

        const dt = Math.min(0.05, (now - lastTime) / 1000);
        lastTime = now;
        update(dt, now);
        frame = requestAnimationFrame(animate);
    };

    setKey(steps[0]);
    fillEl.style.clipPath = 'inset(100% 0 0 0)';
    document.addEventListener('keydown', onKeyDown);

    game = { id, destroy };

    void root.offsetWidth;
    root.classList.add('on');
    frame = requestAnimationFrame(animate);
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (data.action === 'start') {
        startKeymash(data.data.id, data.data.config || {});
    } else if (data.action === 'stop') {

        if (game) game.destroy();
    }
});

$(function () {
    post('uiReady');
});
