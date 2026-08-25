/* ============================================================
   FreeFlow landing page: behaviour
   ============================================================ */

const REDUCED = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
/* maps v from [a,b] onto 0..1, clamped */
const span = (v, a, b) => clamp((v - a) / (b - a));

/* ------------------------------------------------------------
   Waveform.
   Same composition as the app's RecordingHUD: a wave travelling
   across the bars, a slow swell and a fast flutter, at unrelated
   frequencies so the pattern never visibly repeats.
   ------------------------------------------------------------ */

function makeWave(canvas, bars = 11) {
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = canvas.width, h = canvas.height;
  canvas.width = w * dpr; canvas.height = h * dpr;
  canvas.style.width = w / 2 + 'px'; canvas.style.height = h / 2 + 'px';
  ctx.scale(dpr, dpr);

  const bw = 2, cw = w / dpr, ch = h / dpr;
  const gap = (cw - bars * bw) / (bars - 1);

  return function draw(time, energy) {
    ctx.clearRect(0, 0, cw, ch);
    ctx.fillStyle = '#fff';
    const centre = (bars - 1) / 2;
    for (let i = 0; i < bars; i++) {
      const travelling = Math.sin(time * 3.1 - i * 0.9);
      const swell      = Math.sin(time * 1.7 + i * 0.35) * 0.7;
      const flutter    = Math.sin(time * 7.3 + i * 2.1) * 0.45;
      const unit  = ((travelling + swell + flutter) / 2.15 + 1) / 2;
      const taper = 1 - (Math.abs(i - centre) / centre) * 0.42;
      const min = 2;
      const bh = min + Math.max(0, (ch - min) * unit * energy * taper);
      const x = i * (bw + gap), y = (ch - bh) / 2;
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(x, y, bw, bh, bw / 2);
      else ctx.rect(x, y, bw, bh);
      ctx.fill();
    }
  };
}

/* ------------------------------------------------------------
   Hero: the headline arrives a word at a time, like dictation.
   ------------------------------------------------------------ */

function splitWords() {
  $$('[data-dictate]').forEach(line => {
    const words = line.textContent.trim().split(/\s+/);
    line.textContent = '';
    words.forEach((word, i) => {
      const s = document.createElement('span');
      s.className = 'w';
      s.textContent = word;
      s.style.opacity = '0';
      s.style.transform = 'translateY(0.42em)';
      line.append(s);
      if (i < words.length - 1) line.append(' ');
    });
  });
}

function playHero() {
  const words = $$('.hero__h1 .w');
  if (REDUCED) {
    words.forEach(w => { w.style.opacity = '1'; w.style.transform = 'none'; });
    return;
  }
  gsap.to(words, {
    opacity: 1, y: 0, duration: 0.5, ease: 'power3.out',
    stagger: 0.055, delay: 0.15,
  });
  gsap.from('.hero__sub, .hero__cta, .specs', {
    opacity: 0, y: 16, duration: 0.7, ease: 'power2.out',
    stagger: 0.09, delay: 0.55,
  });
}

/* ------------------------------------------------------------
   Nav + rail
   ------------------------------------------------------------ */

function chrome() {
  const nav = $('.nav');
  const onScroll = () => nav.classList.toggle('is-stuck', window.scrollY > 12);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  const items = $$('.rail li');
  const sections = $$('[data-section]');
  if (!items.length) return;

  const io = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const id = e.target.id;
      items.forEach(li => li.classList.toggle('is-on', li.dataset.rail === id));
    });
  }, { rootMargin: '-45% 0px -45% 0px' });
  sections.forEach(s => s.id && io.observe(s));
}

/* ------------------------------------------------------------
   Copy the clone command
   ------------------------------------------------------------ */

function copyButton() {
  const btn = $('[data-copy]');
  if (!btn) return;
  const label = $('.cmd__label', btn);
  const original = label ? label.textContent : '';
  btn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(btn.dataset.copy);
      btn.classList.add('is-copied');
      if (label) label.textContent = 'Copied';
      setTimeout(() => {
        btn.classList.remove('is-copied');
        if (label) label.textContent = original;
      }, 1800);
    } catch {
      /* clipboard blocked (insecure context or denied): select instead */
      const r = document.createRange();
      r.selectNodeContents($('code', btn));
      const sel = getSelection();
      sel.removeAllRanges(); sel.addRange(r);
    }
  });
}

/* ------------------------------------------------------------
   The demo.
   Scroll position drives a single render(progress) so every
   frame is deterministic and scrubbing backwards works.
   ------------------------------------------------------------ */

const RAW = [
  { t: 'um ', f: 1 }, { t: 'so ', f: 1 }, { t: 'i was thinking ' },
  { t: 'uh ', f: 1 }, { t: 'maybe we could push the launch to next week ' },
  { t: 'and ' }, { t: 'uh ', f: 1 },
  { t: 'let the team actually finish testing before we ship it' },
];
const CLEAN = 'I was thinking we could push the launch to next week and let the team finish testing before we ship.';
const RAW_LEN = RAW.reduce((n, x) => n + x.t.length, 0);

function rawUpTo(n) {
  let out = '', used = 0;
  for (const tok of RAW) {
    if (used >= n) break;
    const take = Math.min(tok.t.length, n - used);
    const piece = tok.t.slice(0, take);
    out += tok.f
      ? `<span class="fill">${piece}</span>`
      : piece.replace(/&/g, '&amp;').replace(/</g, '&lt;');
    used += take;
  }
  return out;
}

function demo() {
  const sec = $('.demo');
  if (!sec) return;

  const field   = $('[data-field]');
  const textEl  = $('[data-text]');
  const caret   = $('[data-caret]');
  const ph      = $('[data-ph]');
  const hud     = $('[data-hud]');
  const pointer = $('[data-pointer]');
  const keycap  = $('[data-keycap]');
  const hint    = $('[data-hint]');
  const legendRaw   = $('[data-legend="raw"]');
  const legendClean = $('[data-legend="clean"]');
  const waveCanvas  = $('[data-wave]');
  const drawWave = waveCanvas ? makeWave(waveCanvas) : null;

  if (REDUCED) {
    textEl.textContent = CLEAN;
    ph.style.opacity = '0';
    legendClean.classList.add('legend--on');
    return;
  }

  let energy = 0.3;

  function render(p) {
    /* pointer travels in and clicks */
    const travel = span(p, 0, 0.12);
    const mock = field.closest('.mock').getBoundingClientRect();
    const f = field.getBoundingClientRect();
    const endX = f.left - mock.left + 46;
    const endY = f.top - mock.top + 34;
    const fromX = mock.width * 0.86, fromY = mock.height * 1.02;
    const px = fromX + (endX - fromX) * ease(travel);
    const py = fromY + (endY - fromY) * ease(travel);
    pointer.style.opacity = p < 0.005 ? 0 : (p > 0.2 ? 0 : 1);
    pointer.style.transform = `translate(${px}px, ${py}px)`;

    /* field focus */
    const focused = p > 0.12;
    field.classList.toggle('is-focus', focused);
    ph.style.opacity = p > 0.14 ? 0 : 1;
    caret.classList.toggle('is-on', focused && p < 0.88);

    /* key held */
    const keyOn = p > 0.17 && p < 0.66;
    keycap.style.opacity = p > 0.15 ? 1 : 0;
    keycap.classList.toggle('is-down', keyOn);

    /* overlay */
    const hudOn = p > 0.18 && p < 0.9;
    hud.style.opacity = hudOn ? 1 : 0;
    hud.style.scale = hudOn ? 1 : 0.9;
    energy = keyOn ? 1 : 0.28;

    /* typing */
    if (p < 0.7) {
      const n = Math.round(RAW_LEN * span(p, 0.24, 0.62));
      textEl.innerHTML = rawUpTo(n);
      textEl.style.opacity = 1;
      legendRaw.classList.add('legend--on');
      legendClean.classList.remove('legend--on');
    } else if (p < 0.78) {
      /* the polish pass: raw dims out */
      textEl.innerHTML = rawUpTo(RAW_LEN);
      textEl.style.opacity = 1 - span(p, 0.7, 0.78) * 0.85;
      legendRaw.classList.add('legend--on');
      legendClean.classList.remove('legend--on');
    } else {
      const t = span(p, 0.78, 0.88);
      textEl.textContent = CLEAN;
      textEl.style.opacity = 0.15 + t * 0.85;
      legendRaw.classList.remove('legend--on');
      legendClean.classList.add('legend--on');
    }

    if (hint) hint.style.opacity = p > 0.04 ? 0 : 1;
  }

  const ease = t => 1 - Math.pow(1 - t, 3);

  ScrollTrigger.create({
    trigger: sec,
    start: 'top top',
    end: 'bottom bottom',
    scrub: true,
    onUpdate: self => render(self.progress),
    onRefresh: self => render(self.progress),
  });

  render(0);

  if (drawWave) {
    const loop = () => {
      drawWave(performance.now() / 1000, energy);
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }
}

/* ------------------------------------------------------------
   Horizontal feature strip
   ------------------------------------------------------------ */

function strip() {
  const sec = $('.box');
  const rail = $('[data-strip]');
  if (!sec || !rail || REDUCED) return;

  let distance = 0;

  const measure = () => {
    distance = Math.max(0, rail.scrollWidth - window.innerWidth + 40);
    sec.style.height = (window.innerHeight + distance) + 'px';
  };
  measure();

  ScrollTrigger.create({
    trigger: sec,
    start: 'top top',
    end: 'bottom bottom',
    scrub: 0.6,
    onRefresh: measure,
    onUpdate: self => {
      rail.style.transform = `translate3d(${-distance * self.progress}px,0,0)`;
    },
  });

  window.addEventListener('resize', () => { measure(); ScrollTrigger.refresh(); });
}

/* ------------------------------------------------------------
   Pipeline: the signal runs to the edge of the machine and stops
   ------------------------------------------------------------ */

function pipeline() {
  const path = $('[data-pipeline]');
  const dot  = $('[data-pipedot]');
  if (!path) return;

  const len = path.getTotalLength();
  path.style.strokeDasharray = len;
  path.style.strokeDashoffset = REDUCED ? 0 : len;
  if (REDUCED) { dot.setAttribute('cx', 700); return; }

  ScrollTrigger.create({
    trigger: '.pipe',
    start: 'top 78%',
    end: 'bottom 55%',
    scrub: 0.5,
    onUpdate: self => {
      path.style.strokeDashoffset = len * (1 - self.progress);
      dot.setAttribute('cx', 40 + 660 * self.progress);
    },
  });
}

/* ------------------------------------------------------------
   Section reveals
   ------------------------------------------------------------ */

function reveals() {
  if (REDUCED) return;
  $$('.sec__head, .sec__body > *, .claim, .term, .term__foot, .close__cta')
    .forEach(el => {
      gsap.from(el, {
        opacity: 0, y: 22, duration: 0.65, ease: 'power2.out',
        scrollTrigger: { trigger: el, start: 'top 88%' },
      });
    });
}

/* ------------------------------------------------------------
   Terminal
   ------------------------------------------------------------ */

const STEPS = [
  [
    ['p', '$ '], ['c', 'brew install xcodegen\n'],
    ['o', 'Pouring xcodegen… done\n\n'],
    ['p', '$ '], ['c', 'git clone https://github.com/getfreeflow/freeflow.git\n'],
    ['o', "Cloning into 'freeflow'… done\n\n"],
    ['p', '$ '], ['c', 'cd freeflow && xcodegen generate\n'],
    ['o', 'Created project at FreeFlow.xcodeproj\n\n'],
    ['p', '$ '], ['c', 'open FreeFlow.xcodeproj\n'],
    ['o', 'Press Run. First build pulls WhisperKit and takes a few minutes.\n'],
    ['ok', '\n✓ FreeFlow.app built\n'],
  ],
  [
    ['o', '# Copy it out of DerivedData first. macOS ties permissions\n'],
    ['o', '# to where the app lives, so run it from /Applications.\n\n'],
    ['p', '$ '], ['c', 'cp -R ~/Library/Developer/Xcode/DerivedData/FreeFlow-*/Build/Products/Debug/FreeFlow.app /Applications/\n\n'],
    ['o', 'Then grant three permissions when asked:\n'],
    ['ok', '  ✓ Microphone        '], ['o', 'to hear you\n'],
    ['ok', '  ✓ Accessibility     '], ['o', 'to place text in other apps\n'],
    ['ok', '  ✓ Input Monitoring  '], ['o', 'to see the trigger key\n\n'],
    ['o', 'Quit and reopen after Input Monitoring. macOS only\n'],
    ['o', 'reads that one at launch.\n'],
  ],
  [
    ['o', '# Ad-hoc signatures change every build, and macOS\n'],
    ['o', '# identifies apps by signature. So every rebuild looks\n'],
    ['o', '# like a new app and your permissions vanish.\n\n'],
    ['o', '# A certificate fixes it permanently.\n\n'],
    ['p', '$ '], ['c', 'echo \'CODE_SIGN_IDENTITY = FreeFlow Local Signing\' > Support/Signing.local.xcconfig\n'],
    ['p', '$ '], ['c', 'xcodegen generate\n\n'],
    ['p', '$ '], ['c', 'codesign -d -r- /Applications/FreeFlow.app\n'],
    ['o', 'designated => identifier "com.freeflow.FreeFlow"\n'],
    ['o', '              and certificate leaf = H"10b03e15…"\n'],
    ['ok', '\n✓ no cdhash, so the identity survives every rebuild\n'],
    ['o', '\nFull commands in the README.\n'],
  ],
];

function terminal() {
  const body = $('[data-term]');
  const tabs = $$('.term__tabs button');
  if (!body) return;

  let token = 0;

  function paint(index, animate) {
    const mine = ++token;
    const parts = STEPS[index];
    body.innerHTML = '';

    if (!animate || REDUCED) {
      body.innerHTML = parts
        .map(([cls, t]) => `<span class="${cls}">${escape_(t)}</span>`).join('');
      return;
    }

    let pi = 0, ci = 0;
    const cursor = document.createElement('span');
    cursor.className = 'term__cursor';

    const tick = () => {
      if (mine !== token) return;
      if (pi >= parts.length) { cursor.remove(); return; }

      const [cls, text] = parts[pi];
      let node = body.lastElementChild;
      if (!node || node.className !== cls || node === cursor) {
        node = document.createElement('span');
        node.className = cls;
        body.append(node);
      }
      /* prompts and output land whole; typed commands go character by character */
      if (cls === 'c') {
        node.textContent += text[ci++];
        if (ci >= text.length) { pi++; ci = 0; }
      } else {
        node.textContent += text;
        pi++;
      }
      body.append(cursor);
      body.scrollTop = body.scrollHeight;
      setTimeout(tick, cls === 'c' ? 13 : 90);
    };
    tick();
  }

  const escape_ = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

  tabs.forEach(btn => {
    btn.addEventListener('click', () => {
      tabs.forEach(b => b.setAttribute('aria-selected', String(b === btn)));
      paint(+btn.dataset.tab, true);
    });
  });

  /* type it out the first time it comes into view */
  let played = false;
  ScrollTrigger.create({
    trigger: '.term', start: 'top 72%',
    onEnter: () => { if (!played) { played = true; paint(0, true); } },
  });
  paint(0, false);
}

/* ------------------------------------------------------------
   Persistent overlay pill
   ------------------------------------------------------------ */

function pill() {
  const el = $('[data-pill]');
  const canvas = $('[data-pillwave]');
  const label = $('[data-pilllabel]');
  if (!el || REDUCED) return;

  const draw = makeWave(canvas);
  let energy = 0.34;

  const LABELS = [
    ['hero',    'listening'],
    ['gap',     'listening'],
    ['demo',    'transcribing'],
    ['box',     'nine tools'],
    ['local',   'on device'],
    ['install', 'four commands'],
    ['faq',     'ask away'],
  ];

  ScrollTrigger.create({
    trigger: '.hero', start: 'bottom 70%',
    onEnter: () => el.classList.add('is-on'),
    onLeaveBack: () => el.classList.remove('is-on'),
  });

  LABELS.forEach(([id, text]) => {
    const target = document.getElementById(id);
    if (!target) return;
    ScrollTrigger.create({
      trigger: target, start: 'top 55%', end: 'bottom 45%',
      onToggle: self => {
        if (!self.isActive) return;
        label.textContent = text;
        energy = id === 'demo' ? 0.95 : 0.4;
      },
    });
  });

  const loop = () => { draw(performance.now() / 1000, energy); requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
}

/* Plain, un-animated terminal for the no-GSAP path. */
function terminalStatic() {
  const body = $('[data-term]');
  if (!body) return;
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const paint = i => {
    body.innerHTML = STEPS[i]
      .map(([cls, t]) => `<span class="${cls}">${esc(t)}</span>`).join('');
  };
  $$('.term__tabs button').forEach(btn => {
    btn.addEventListener('click', () => {
      $$('.term__tabs button').forEach(b => b.setAttribute('aria-selected', String(b === btn)));
      paint(+btn.dataset.tab);
    });
  });
  paint(0);
}

/* ------------------------------------------------------------ */

function boot() {
  splitWords();
  chrome();
  copyButton();

  if (typeof gsap === 'undefined' || typeof ScrollTrigger === 'undefined') {
    /* CDN blocked or offline. Unpin everything so the page stays readable
       and the feature strip becomes a normal horizontal scroller. */
    document.documentElement.classList.add('no-gsap');
    $$('.hero__h1 .w').forEach(w => { w.style.opacity = '1'; w.style.transform = 'none'; });
    const t = $('[data-text]'); if (t) t.textContent = CLEAN;
    const ph = $('[data-ph]'); if (ph) ph.style.opacity = '0';
    terminalStatic();
    return;
  }

  gsap.registerPlugin(ScrollTrigger);
  playHero();
  demo();
  strip();
  pipeline();
  reveals();
  terminal();
  pill();

  window.addEventListener('load', () => ScrollTrigger.refresh());
}

document.addEventListener('DOMContentLoaded', boot);
