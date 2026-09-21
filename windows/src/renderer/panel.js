// The panel that drops out of the top edge when the tray icon is clicked.

const notch = document.getElementById('notch');
const body = document.getElementById('body');
const pillText = document.getElementById('pillText');
const pillDot = document.getElementById('pillDot');

const WIDTH = 460;
let state = null;
let showSettings = false;
let open = false;

document.getElementById('mark').innerHTML = [7, 11, 13, 9, 6]
  .map((height) => `<i style="height:${height}px"></i>`)
  .join('');

/** Best-effort names for the usual trigger keys. The stored keycode is what
 *  actually matters; this is only what we show. */
const KEY_NAMES = {
  56: 'Left Alt',
  3640: 'Right Alt',
  29: 'Left Ctrl',
  3613: 'Right Ctrl',
  42: 'Left Shift',
  54: 'Right Shift',
  3675: 'Left Win',
  3676: 'Right Win',
  58: 'Caps Lock',
};

function keyName(keycode) {
  return KEY_NAMES[keycode] || `Key ${keycode}`;
}

function escapeHtml(value) {
  const node = document.createElement('span');
  node.textContent = value;
  return node.innerHTML;
}

function relative(iso) {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr ago`;
  return `${Math.floor(seconds / 86400)} d ago`;
}

function timeSaved(seconds) {
  // The same rough measure the Mac build uses: speaking beats typing about 3 to 1.
  const saved = (seconds * 2) / 3600;
  return saved < 1 ? `${Math.round(saved * 60)} min` : `${saved.toFixed(1)} hr`;
}

function statusPill() {
  if (!state) return ['Idle', 'var(--tertiary)'];
  switch (state.phase) {
    case 'recording':
      return ['Listening', 'var(--live)'];
    case 'transcribing':
    case 'polishing':
      return ['Working', 'var(--caution)'];
    case 'preparing':
      return ['Loading', 'var(--caution)'];
    case 'failed':
      return ['Error', 'var(--live)'];
    default:
      return state.modelReady ? ['Ready', 'var(--good)'] : ['Idle', 'var(--tertiary)'];
  }
}

function headline() {
  if (!state) return 'Starting up';
  if (state.phase === 'recording') return state.latched ? 'Listening, locked on' : 'Listening';
  if (state.phase === 'transcribing') return 'Transcribing';
  if (state.phase === 'polishing') return 'Cleaning up';
  if (state.phase === 'preparing') return state.statusMessage || 'Getting the speech model ready';
  if (state.phase === 'failed') return state.statusMessage || 'Something went wrong';
  if (!state.modelReady) return 'Getting the speech model ready';
  return `Hold <span class="keycap">${keyName(state.settings.triggerKeycode)}</span> to talk`;
}

function subline() {
  if (!state) return '';
  if (state.phase === 'recording') {
    return state.latched ? 'Tap the key again to finish' : 'Let go to insert, esc to cancel';
  }
  if (!state.modelReady) return 'This happens once, then it runs on this machine';
  const parts = ['Double-tap to lock it on'];
  if (!state.hasKey) parts.push('no Groq key, inserting raw transcripts');
  return parts.join(' · ');
}

function renderMain() {
  const entries = state?.history ?? [];
  const stats = state?.stats ?? { totalWords: 0, totalDictations: 0, totalSeconds: 0 };

  return `
    <div class="status">
      <div class="tile">${icon('mic', 17)}</div>
      <div>
        <div class="headline">${headline()}</div>
        <div class="subline">${escapeHtml(subline())}</div>
      </div>
    </div>

    ${
      state?.statusMessage && state.phase !== 'preparing' && state.phase !== 'failed'
        ? `<div class="banner caution">${icon('alert', 13)}<span>${escapeHtml(state.statusMessage)}</span></div>`
        : ''
    }

    <div class="stats">
      <div class="stat"><b>${stats.totalWords.toLocaleString()}</b><span>words</span></div>
      <div class="stat"><b>${stats.totalDictations.toLocaleString()}</b><span>dictations</span></div>
      <div class="stat"><b>${timeSaved(stats.totalSeconds)}</b><span>saved</span></div>
    </div>

    <div>
      <div class="section-head">
        History <span class="count">${entries.length || ''}</span>
        <span class="spacer"></span>
        ${entries.length ? '<button class="ghost small" id="clear">Clear</button>' : ''}
      </div>
      ${
        entries.length === 0
          ? `<div class="empty">Nothing yet. Hold ${keyName(
              state?.settings.triggerKeycode ?? 0
            )} and say something.</div>`
          : `<div class="list">${entries.map(entryRow).join('')}</div>`
      }
    </div>
  `;
}

function entryRow(entry) {
  return `
    <div class="entry" data-id="${entry.id}">
      <div style="flex:1;min-width:0">
        <div class="text">${escapeHtml(entry.text)}</div>
        <div class="meta">${escapeHtml(entry.app)} · ${relative(entry.at)}${entry.pinned ? ' · pinned' : ''}</div>
      </div>
      <div class="actions">
        <button class="ghost square" data-act="copy" title="Copy">${icon('copy', 12)}</button>
        <button class="ghost square" data-act="pin" title="${entry.pinned ? 'Unpin' : 'Pin'}">${icon('pin', 12)}</button>
        <button class="ghost square" data-act="delete" title="Delete">${icon('trash', 12)}</button>
      </div>
    </div>
  `;
}

function renderSettings() {
  const settings = state.settings;
  return `
    <div class="settings">
      <div class="field">
        <div>Trigger key<small>Hold it to talk, double-tap to lock on</small></div>
        <button class="ghost" id="captureKey">${keyName(settings.triggerKeycode)}</button>
      </div>

      <div class="field">
        <div>Speech model<small>Windows transcribes on the processor, so smaller is quicker</small></div>
        <select id="model">
          <option value="base.en"${settings.model === 'base.en' ? ' selected' : ''}>Base (fastest)</option>
          <option value="small.en"${settings.model === 'small.en' ? ' selected' : ''}>Small (recommended)</option>
          <option value="large-v3-turbo-q5_0"${
            settings.model === 'large-v3-turbo-q5_0' ? ' selected' : ''
          }>Large v3 Turbo (most accurate)</option>
        </select>
      </div>

      <div class="field">
        <div>NVIDIA acceleration<small>Downloads a 643MB CUDA build. Only useful with an NVIDIA card.</small></div>
        <input type="checkbox" id="cuda"${settings.useCuda ? ' checked' : ''} />
      </div>

      <div class="field">
        <div>Clean up with Groq<small>The one thing that leaves this machine. Off means raw transcripts.</small></div>
        <input type="checkbox" id="cleanup"${settings.cleanupEnabled ? ' checked' : ''} />
      </div>

      <div class="field">
        <div>Groq API key<small>Stored in plain text in your app data folder</small></div>
        <input type="password" id="apiKey" placeholder="${state.hasKey ? 'Saved' : 'gsk_…'}" style="width:170px" />
      </div>

      <div class="field">
        <div>Recording overlay<small>Drops out of the top of the screen while you talk</small></div>
        <input type="checkbox" id="overlay"${settings.showOverlay ? ' checked' : ''} />
      </div>

      <div class="field">
        <div>Sound when a take ends</div>
        <input type="checkbox" id="sounds"${settings.playSounds ? ' checked' : ''} />
      </div>

      <div class="field">
        <div>Your data<small>Settings, history and the API key live here</small></div>
        <button class="ghost" id="openFolder">${icon('folder', 13)} Open folder</button>
      </div>
    </div>
  `;
}

function render() {
  if (!state) return;

  notch.style.setProperty('--w', open ? `${WIDTH}px` : '180px');
  notch.style.setProperty('--radius', open ? '24px' : '12px');
  notch.classList.toggle('open', open);

  const [text, colour] = statusPill();
  pillText.textContent = text;
  pillDot.style.background = colour;

  body.innerHTML =
    (showSettings ? renderSettings() : renderMain()) +
    `<div class="footer">
       <button class="ghost" id="toggleSettings">${icon(showSettings ? 'history' : 'settings', 13)} ${
         showSettings ? 'Back' : 'Settings'
       }</button>
       <span class="spacer"></span>
       <button class="ghost" id="quit">${icon('power', 13)} Quit</button>
     </div>`;

  // The panel is only as tall as its content, so the window can be sized to match
  // and stop swallowing clicks on the rest of the screen.
  const height = notch.querySelector('.contents').scrollHeight;
  notch.style.setProperty('--h', open ? `${height}px` : '0px');

  wire();
}

function wire() {
  document.getElementById('quit').onclick = () => window.freeflow.send('panel:quit');
  document.getElementById('toggleSettings').onclick = () => {
    showSettings = !showSettings;
    render();
  };

  const clear = document.getElementById('clear');
  if (clear) {
    clear.onclick = async () => {
      const kept = state.history.filter((entry) => entry.pinned);
      state = await window.freeflow.invoke('history:update', kept);
      render();
    };
  }

  for (const button of document.querySelectorAll('.entry [data-act]')) {
    button.onclick = async () => {
      const id = button.closest('.entry').dataset.id;
      const entry = state.history.find((candidate) => candidate.id === id);
      if (!entry) return;

      if (button.dataset.act === 'copy') {
        await navigator.clipboard.writeText(entry.text);
        button.innerHTML = icon('check', 12);
        return;
      }

      const next =
        button.dataset.act === 'pin'
          ? state.history.map((candidate) =>
              candidate.id === id ? { ...candidate, pinned: !candidate.pinned } : candidate
            )
          : state.history.filter((candidate) => candidate.id !== id);

      state = await window.freeflow.invoke('history:update', next);
      render();
    };
  }

  if (!showSettings) return;

  const set = async (changes) => {
    state = await window.freeflow.invoke('settings:set', changes);
    render();
  };

  document.getElementById('model').onchange = (event) => set({ model: event.target.value });
  document.getElementById('cuda').onchange = (event) => set({ useCuda: event.target.checked });
  document.getElementById('cleanup').onchange = (event) => set({ cleanupEnabled: event.target.checked });
  document.getElementById('overlay').onchange = (event) => set({ showOverlay: event.target.checked });
  document.getElementById('sounds').onchange = (event) => set({ playSounds: event.target.checked });
  document.getElementById('openFolder').onclick = () => window.freeflow.invoke('folder:open');

  const capture = document.getElementById('captureKey');
  capture.onclick = async () => {
    capture.textContent = 'Press a key…';
    const keycode = await window.freeflow.invoke('trigger:capture');
    if (keycode === null) {
      render();
      return;
    }
    await set({ triggerKeycode: keycode, triggerLabel: keyName(keycode) });
  };

  const apiKey = document.getElementById('apiKey');
  apiKey.onchange = async () => {
    if (!apiKey.value.trim()) return;
    state = await window.freeflow.invoke('key:set', apiKey.value.trim());
    render();
  };
}

window.freeflow.on('state', (next) => {
  state = next;
  render();
});

window.freeflow.on('panel:open', () => {
  open = true;
  notch.classList.remove('closing');
  render();
});

window.freeflow.on('panel:close', () => {
  open = false;
  showSettings = false;
  notch.classList.add('closing');
  render();
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') window.freeflow.send('panel:hide');
});

window.freeflow.invoke('state:get').then((initial) => {
  state = initial;
  render();
});
