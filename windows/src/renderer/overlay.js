// The recording overlay. Grows out of the top edge of the screen while you talk.

const notch = document.getElementById('notch');
const earLeft = document.getElementById('earLeft');
const earRight = document.getElementById('earRight');
const row = document.getElementById('row');

const COLLAPSED = { width: 150, height: 0 };
const BAND = 34;

/** Wide enough for the discard and insert buttons when the row is showing, and
 *  only as wide as the level meter when it isn't. */
const OPEN_WIDTH = { plain: 168, withRow: 268 };

let state = { phase: 'idle', latched: false, outcome: 'inserted', statusMessage: '' };
let open = false;
let level = 0;

function mark() {
  return '<span class="mark">' +
    [6, 9, 11, 8, 5].map((h) => `<i style="height:${h}px"></i>`).join('') +
    '</span>';
}

/** How tall the part below the band is, if anything. */
function rowHeight() {
  if (state.phase === 'recording' && state.latched) return 36;
  if (state.phase === 'failed') return 42;
  if (state.phase === 'idle' && state.outcome !== 'inserted') return 30;
  return 0;
}

function render() {
  const extra = rowHeight();
  const width = open ? (extra > 0 ? OPEN_WIDTH.withRow : OPEN_WIDTH.plain) : COLLAPSED.width;
  const height = open ? BAND + extra : COLLAPSED.height;

  notch.style.setProperty('--w', `${width}px`);
  notch.style.setProperty('--h', `${height}px`);
  notch.style.setProperty('--radius', extra > 0 ? '18px' : '14px');
  notch.classList.toggle('open', open);

  // Ears
  if (state.phase === 'recording') {
    earLeft.innerHTML = '<span class="dot"></span>';
    earRight.innerHTML = state.latched
      ? `<span style="opacity:.45">${icon('lock', 11)}</span>`
      : '<canvas class="bars" width="60" height="26" style="width:30px;height:13px"></canvas>';
  } else if (state.phase === 'transcribing' || state.phase === 'polishing' || state.phase === 'preparing') {
    earLeft.innerHTML = mark();
    earRight.innerHTML = '<span class="dots"><span></span><span></span><span></span></span>';
  } else if (state.phase === 'failed') {
    earLeft.innerHTML = `<span style="color:var(--caution)">${icon('alert', 13)}</span>`;
    earRight.innerHTML = '';
  } else if (state.outcome === 'copied') {
    earLeft.innerHTML = icon('clipboardCheck', 13);
    earRight.innerHTML = '';
  } else if (state.outcome === 'discarded') {
    earLeft.innerHTML = `<span style="opacity:.7">${icon('history', 13)}</span>`;
    earRight.innerHTML = '';
  } else {
    earLeft.innerHTML = mark();
    earRight.innerHTML = `<span style="color:var(--good)">${icon('check', 13, 2.6)}</span>`;
  }

  // The row below the band
  row.hidden = extra === 0;
  if (extra > 0) {
    if (state.phase === 'recording' && state.latched) {
      row.innerHTML =
        `<button class="circle-button" id="discard" title="Don't insert (kept in History)">${icon('x', 11, 2.6)}</button>` +
        '<canvas class="bars" width="140" height="30" style="width:70px;height:15px"></canvas>' +
        `<button class="circle-button prominent" id="accept" title="Stop and insert">${icon('check', 11, 2.6)}</button>`;
      document.getElementById('discard').onclick = () => window.freeflow.send('overlay:discard');
      document.getElementById('accept').onclick = () => window.freeflow.send('overlay:accept');
    } else if (state.phase === 'failed') {
      row.innerHTML = `<span class="message">${escapeHtml(state.statusMessage || 'Something went wrong')}</span>`;
    } else {
      row.innerHTML = `<span class="message">${
        state.outcome === 'copied' ? 'Copied to clipboard' : 'Saved to History'
      }</span>`;
    }
  }
}

function escapeHtml(value) {
  const node = document.createElement('span');
  node.textContent = value;
  return node.innerHTML;
}

// The same bars as the Mac build: three sine components at unrelated frequencies so
// the pattern never visibly repeats, with the mic level only scaling how far they
// swing, low-pass filtered so a jump in volume eases in instead of snapping.
let smoothed = 0;
let lastFrame = 0;

function drawBars(now) {
  const seconds = now / 1000;
  const delta = lastFrame === 0 ? 1 / 60 : Math.min(seconds - lastFrame, 0.1);
  lastFrame = seconds;
  smoothed += (Math.min(Math.max(level, 0), 1) - smoothed) * (1 - Math.exp(-delta / 0.09));
  const energy = 0.3 + smoothed * 0.95;

  for (const canvas of document.querySelectorAll('canvas.bars')) {
    const context = canvas.getContext('2d');
    const count = canvas.width > 100 ? 13 : 7;
    const barWidth = 4;
    const spacing = (canvas.width - count * barWidth) / (count - 1);
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = 'rgba(255,255,255,0.92)';

    for (let index = 0; index < count; index += 1) {
      const phase = index;
      const travelling = Math.sin(seconds * 3.1 - phase * 0.9);
      const swell = Math.sin(seconds * 1.7 + phase * 0.35) * 0.7;
      const flutter = Math.sin(seconds * 7.3 + phase * 2.1) * 0.45;
      const unit = ((travelling + swell + flutter) / 2.15 + 1) / 2;
      const centre = (count - 1) / 2;
      const taper = 1 - (Math.abs(phase - centre) / centre) * 0.42;
      const minimum = 5;
      const height = minimum + Math.max(0, (canvas.height - minimum) * unit * energy * taper);
      const x = index * (barWidth + spacing);
      const y = (canvas.height - height) / 2;
      context.beginPath();
      context.roundRect(x, y, barWidth, height, barWidth / 2);
      context.fill();
    }
  }
  requestAnimationFrame(drawBars);
}
requestAnimationFrame(drawBars);

window.freeflow.on('state', (next) => {
  state = next;
  render();
});
window.freeflow.on('level', (value) => {
  level = value;
});
window.freeflow.on('overlay:show', () => {
  open = true;
  notch.classList.remove('closing');
  render();
});
window.freeflow.on('overlay:hide', () => {
  open = false;
  notch.classList.add('closing');
  render();
});

window.freeflow.invoke('state:get').then((initial) => {
  if (initial) {
    state = initial;
    render();
  }
});
render();
