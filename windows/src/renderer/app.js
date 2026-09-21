// The main window: every screen the Mac build has, minus Meetings, which is not
// ported. One state object arrives from the main process and each screen renders
// from it, so nothing here keeps a second copy that could drift.

const nav = document.getElementById('nav');
const main = document.getElementById('main');
const pillDot = document.getElementById('pillDot');
const pillText = document.getElementById('pillText');

document.getElementById('mark').innerHTML = [7, 11, 14, 10, 6]
  .map((height) => `<i style="height:${height}px"></i>`)
  .join('');

const SCREENS = [
  { id: 'home', name: 'Dashboard', icon: 'home' },
  { id: 'history', name: 'History', icon: 'history' },
  { id: 'insights', name: 'Insights', icon: 'chart' },
  { id: 'vocabulary', name: 'Vocabulary', icon: 'book' },
  { id: 'snippets', name: 'Snippets', icon: 'zap' },
  { id: 'actions', name: 'Actions', icon: 'wand' },
  { id: 'style', name: 'Style', icon: 'type' },
  { id: 'settings', name: 'Settings', icon: 'settings' },
];

let state = null;
let screen = 'home';
let search = '';
/** Which row is expanded for editing, so a re-render doesn't collapse it. */
let editing = null;

// MARK: - Helpers

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

const keyName = (code) => KEY_NAMES[code] || `Key ${code}`;

function esc(value) {
  const node = document.createElement('span');
  node.textContent = value ?? '';
  return node.innerHTML;
}

function relative(iso) {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr ago`;
  if (seconds < 172800) return 'yesterday';
  return `${Math.floor(seconds / 86400)} days ago`;
}

/** Speaking beats typing about three to one, the same measure the Mac build uses. */
function timeSaved(seconds) {
  const saved = (seconds * 2) / 3600;
  if (saved < 1) return `${Math.round(saved * 60)} min`;
  return `${saved.toFixed(1)} hr`;
}

const uid = () => Math.random().toString(36).slice(2, 10);

// MARK: - Shell

function statusPill() {
  if (!state) return ['Starting up', 'var(--tertiary)'];
  switch (state.phase) {
    case 'recording':
      return [state.latched ? 'Listening, locked' : 'Listening', 'var(--live)'];
    case 'transcribing':
      return ['Transcribing', 'var(--caution)'];
    case 'polishing':
      return ['Cleaning up', 'var(--caution)'];
    case 'preparing':
      return ['Downloading', 'var(--caution)'];
    case 'failed':
      return ['Something failed', 'var(--live)'];
    default:
      return state.modelReady ? ['Ready', 'var(--good)'] : ['Getting ready', 'var(--tertiary)'];
  }
}

function renderNav() {
  nav.innerHTML = SCREENS.map((item) => {
    const counts = {
      history: state?.history?.length,
      vocabulary: state?.vocabulary?.length,
      snippets: state?.snippets?.length,
      actions: state?.actions?.length,
      style: state?.style?.length,
    };
    const count = counts[item.id];
    return `<button data-screen="${item.id}" class="${screen === item.id ? 'on' : ''}">
      ${icon(item.icon, 15, 1.8)} ${item.name}
      ${count ? `<span class="count">${count}</span>` : ''}
    </button>`;
  }).join('');

  for (const button of nav.querySelectorAll('button')) {
    button.onclick = () => {
      screen = button.dataset.screen;
      editing = null;
      search = '';
      render();
    };
  }
}

function render() {
  if (!state) return;

  document.documentElement.dataset.theme = state.theme === 'light' ? 'light' : 'dark';

  const [text, colour] = statusPill();
  pillText.textContent = text;
  pillDot.style.background = colour;

  renderNav();

  const screens = {
    home: homeScreen,
    history: historyScreen,
    insights: insightsScreen,
    vocabulary: vocabularyScreen,
    snippets: snippetsScreen,
    actions: actionsScreen,
    style: styleScreen,
    settings: settingsScreen,
  };

  main.innerHTML = (screens[screen] || homeScreen)();
  wire();
}

function header(title, subtitle) {
  return `<div class="head"><h1>${title}</h1><p>${subtitle}</p></div>`;
}

// MARK: - Dashboard

function homeScreen() {
  const stats = state.stats;
  const key = keyName(state.settings.triggerKeycode);

  let what = `Hold <span class="keycap">${key}</span> to talk`;
  let why = 'Let go and the text lands where your cursor is. Double-tap to lock it on.';

  if (state.phase === 'recording') {
    what = state.latched ? 'Listening, locked on' : 'Listening';
    why = state.latched ? 'Tap the key again to finish' : 'Let go to insert, esc to throw it away';
  } else if (state.phase === 'transcribing') {
    what = 'Transcribing';
    why = 'Running on this machine';
  } else if (state.phase === 'polishing') {
    what = 'Cleaning up';
    why = 'Sending the transcript to Groq';
  } else if (state.phase === 'preparing' || !state.modelReady) {
    what = 'Getting the speech model ready';
    why = state.statusMessage || 'This happens once, then it all runs on this machine';
  } else if (state.phase === 'failed') {
    what = 'Something went wrong';
    why = state.statusMessage || 'Try again';
  }

  const recent = (state.history || []).slice(0, 5);

  return (
    header('Dashboard', 'What FreeFlow has been doing.') +
    (!state.hasKey
      ? `<div class="banner warn">${icon('alert', 15)}<span><b>No Groq key.</b> Dictation works and inserts the raw transcript. Add a key in Settings to get the cleanup pass.</span></div>`
      : '') +
    `<div class="card"><div class="status">
      <div class="tile">${icon('mic', 20, 1.8)}</div>
      <div class="grow"><div class="what">${what}</div><div class="why">${esc(why)}</div></div>
    </div></div>

    <div class="grid">
      <div class="card stat"><b>${stats.totalWords.toLocaleString()}</b><span>words dictated</span></div>
      <div class="card stat"><b>${stats.totalDictations.toLocaleString()}</b><span>dictations</span></div>
      <div class="card stat"><b>${timeSaved(stats.totalSeconds)}</b><span>time saved</span></div>
      <div class="card stat"><b>${(state.vocabulary || []).length}</b><span>vocabulary terms</span></div>
    </div>

    <div class="card">
      <div class="section-title">Recent<span class="spacer"></span>
        <button class="b quiet" data-goto="history">All history</button>
      </div>
      ${
        recent.length === 0
          ? `<div class="empty">Nothing yet. Hold ${key} and say something.</div>`
          : `<div class="rows">${recent
              .map(
                (entry) => `<div class="row"><div class="grow">
                  <div class="text">${esc(entry.text)}</div>
                  <div class="meta">${esc(entry.app)} · ${relative(entry.at)}</div>
                </div></div>`
              )
              .join('')}</div>`
      }
    </div>`
  );
}

// MARK: - History

function historyScreen() {
  const needle = search.trim().toLowerCase();
  const entries = (state.history || []).filter(
    (entry) => !needle || entry.text.toLowerCase().includes(needle) || entry.app.toLowerCase().includes(needle)
  );

  return (
    header('History', 'Every dictation, newest first. Pinned ones are never culled.') +
    `<div class="card">
      <div class="section-title">
        <input type="text" id="search" placeholder="Search" value="${esc(search)}" style="width:220px" />
        <span class="spacer"></span>
        <span class="tag">${entries.length} shown</span>
        ${state.history.length ? '<button class="b quiet danger" id="clear">Clear unpinned</button>' : ''}
      </div>
      ${
        entries.length === 0
          ? `<div class="empty">${needle ? 'Nothing matches that.' : 'Nothing yet.'}</div>`
          : `<div class="rows">${entries
              .map(
                (entry) => `<div class="row" data-id="${entry.id}">
                  <div class="grow">
                    <div class="text">${esc(entry.text)}</div>
                    <div class="meta">${esc(entry.app)} · ${relative(entry.at)}${
                      entry.pinned ? ' · pinned' : ''
                    }</div>
                  </div>
                  <div class="tools">
                    <button class="b sq" data-act="copy" title="Copy">${icon('copy', 14)}</button>
                    <button class="b sq" data-act="pin" title="${entry.pinned ? 'Unpin' : 'Pin'}" ${
                      entry.pinned ? 'style="color:var(--accent)"' : ''
                    }>${icon('pin', 14)}</button>
                    <button class="b sq danger" data-act="delete" title="Delete">${icon('trash', 14)}</button>
                  </div>
                </div>`
              )
              .join('')}</div>`
      }
    </div>`
  );
}

// MARK: - Insights

function insightsScreen() {
  const days = state.days || [];
  const recent = lastDays(days, 30);
  const peak = Math.max(1, ...recent.map((day) => day.words));
  const total = recent.reduce((sum, day) => sum + day.words, 0);
  const active = recent.filter((day) => day.dictations > 0).length;
  const seconds = recent.reduce((sum, day) => sum + day.seconds, 0);
  const wordsPerMinute = seconds > 0 ? Math.round((total / seconds) * 60) : 0;

  const apps = {};
  for (const day of recent) {
    for (const [name, words] of Object.entries(day.apps || {})) {
      apps[name] = (apps[name] || 0) + words;
    }
  }
  const ranked = Object.entries(apps).sort((a, b) => b[1] - a[1]).slice(0, 6);

  return (
    header('Insights', 'The last thirty days.') +
    `<div class="grid">
      <div class="card stat"><b>${total.toLocaleString()}</b><span>words this month</span></div>
      <div class="card stat"><b>${wordsPerMinute || '–'}</b><span>words per minute</span></div>
      <div class="card stat"><b>${active}</b><span>days used</span></div>
      <div class="card stat"><b>${timeSaved(seconds)}</b><span>saved this month</span></div>
    </div>

    <div class="card">
      <div class="section-title">Words per day</div>
      <div class="chart">
        ${recent
          .map(
            (day) =>
              `<div class="bar ${day.words === 0 ? 'none' : ''}" style="height:${Math.max(
                2,
                (day.words / peak) * 100
              )}%" title="${day.date}: ${day.words} words"></div>`
          )
          .join('')}
      </div>
      <div class="axis"><span>${recent[0]?.date ?? ''}</span><span>${
        recent[recent.length - 1]?.date ?? ''
      }</span></div>
    </div>

    <div class="card">
      <div class="section-title">Where the words went</div>
      ${
        ranked.length === 0
          ? '<div class="empty">Nothing recorded yet.</div>'
          : `<div class="rows">${ranked
              .map(
                ([name, words]) => `<div class="row">
                  <div class="grow"><div class="text">${esc(name)}</div>
                    <div class="meta">${Math.round((words / Math.max(total, 1)) * 100)}% of your words</div>
                  </div>
                  <span class="tag">${words.toLocaleString()}</span>
                </div>`
              )
              .join('')}</div>`
      }
    </div>`
  );
}

/** Fills the gaps, so a day with nothing dictated is a gap in the chart rather
 *  than a missing bar that silently shortens the month. */
function lastDays(days, count) {
  const byDate = new Map(days.map((day) => [day.date, day]));
  const out = [];
  for (let back = count - 1; back >= 0; back -= 1) {
    const date = new Date();
    date.setDate(date.getDate() - back);
    const key = date.toISOString().slice(0, 10);
    out.push(byDate.get(key) || { date: key, words: 0, dictations: 0, seconds: 0, apps: {} });
  }
  return out;
}

// MARK: - Vocabulary

function vocabularyScreen() {
  const terms = state.vocabulary || [];
  return (
    header(
      'Vocabulary',
      'The words it keeps getting wrong: names, colleagues, products, acronyms. Anything that sounds close gets corrected to your spelling.'
    ) +
    `<div class="card">
      <div class="section-title">Your terms<span class="spacer"></span><span class="tag">${terms.length}</span></div>
      ${
        terms.length === 0
          ? '<div class="empty">No terms yet.</div>'
          : `<div class="chips">${terms
              .map(
                (term, index) =>
                  `<span class="chip">${esc(term)}<button data-remove="${index}" title="Remove">${icon(
                    'x',
                    12
                  )}</button></span>`
              )
              .join('')}</div>`
      }
      <div class="adder">
        <input type="text" id="newTerm" placeholder="e.g. Kubernetes, Grafana, Postgres" />
        <button class="b primary" id="addTerm">${icon('plus', 14)} Add</button>
      </div>
    </div>`
  );
}

// MARK: - Snippets

function snippetsScreen() {
  const items = state.snippets || [];
  return (
    header(
      'Snippets',
      'Say two words, insert a paragraph. Expanded before the cleanup pass, so the result still gets shaped for wherever it is going.'
    ) +
    `<div class="card">
      <div class="section-title">Your snippets<span class="spacer"></span><span class="tag">${items.length}</span></div>
      ${
        items.length === 0
          ? '<div class="empty">No snippets yet.</div>'
          : `<div class="rows">${items
              .map((item) =>
                editing === item.id
                  ? `<div class="row"><div class="grow">
                      <input type="text" data-edit="trigger" value="${esc(item.trigger)}" style="width:100%;margin-bottom:8px" />
                      <textarea data-edit="expansion">${esc(item.expansion)}</textarea>
                      <div style="display:flex;gap:8px;margin-top:8px">
                        <button class="b primary" data-save="${item.id}">Save</button>
                        <button class="b quiet" data-cancel="1">Cancel</button>
                      </div>
                    </div></div>`
                  : `<div class="row" data-id="${item.id}">
                      <div class="grow">
                        <div class="text"><b>${esc(item.trigger)}</b> → ${esc(
                          item.expansion.length > 90 ? `${item.expansion.slice(0, 90)}…` : item.expansion
                        )}</div>
                        <div class="meta">${item.enabled ? 'On' : 'Off'}</div>
                      </div>
                      <div class="tools">
                        <button class="b sq" data-act="toggle" title="On or off">${icon('check', 14)}</button>
                        <button class="b sq" data-act="edit" title="Edit">${icon('edit', 14)}</button>
                        <button class="b sq danger" data-act="delete" title="Delete">${icon('trash', 14)}</button>
                      </div>
                    </div>`
              )
              .join('')}</div>`
      }
      <div class="adder">
        <input type="text" id="newTrigger" placeholder="Trigger, e.g. my address" style="max-width:200px" />
        <input type="text" id="newExpansion" placeholder="What it expands into" />
        <button class="b primary" id="addSnippet">${icon('plus', 14)} Add</button>
      </div>
    </div>`
  );
}

// MARK: - Actions

function actionsScreen() {
  const items = state.actions || [];
  return (
    header(
      'Actions',
      'Saved instructions you can run over any text. These are the prompts the cleanup model is given when you ask for one by name.'
    ) +
    `<div class="card">
      <div class="section-title">Your actions<span class="spacer"></span><span class="tag">${items.length}</span></div>
      <div class="rows">${items
        .map((item) =>
          editing === item.id
            ? `<div class="row"><div class="grow">
                <input type="text" data-edit="name" value="${esc(item.name)}" style="width:100%;margin-bottom:8px" />
                <textarea data-edit="prompt">${esc(item.prompt)}</textarea>
                <div style="display:flex;gap:8px;margin-top:8px">
                  <button class="b primary" data-save="${item.id}">Save</button>
                  <button class="b quiet" data-cancel="1">Cancel</button>
                </div>
              </div></div>`
            : `<div class="row" data-id="${item.id}">
                <div class="tile" style="width:34px;height:34px;border-radius:8px">${icon(item.icon, 16, 1.8)}</div>
                <div class="grow">
                  <div class="text">${esc(item.name)}</div>
                  <div class="meta">${esc(
                    item.prompt.length > 110 ? `${item.prompt.slice(0, 110)}…` : item.prompt
                  )}</div>
                </div>
                <div class="tools">
                  <button class="b sq" data-act="edit" title="Edit">${icon('edit', 14)}</button>
                  <button class="b sq danger" data-act="delete" title="Delete">${icon('trash', 14)}</button>
                </div>
              </div>`
        )
        .join('')}</div>
      <div class="adder">
        <input type="text" id="newAction" placeholder="Name, e.g. Make it a changelog" />
        <button class="b primary" id="addAction">${icon('plus', 14)} Add</button>
      </div>
    </div>`
  );
}

// MARK: - Style

function styleScreen() {
  const rules = state.style || [];
  return (
    header(
      'Style',
      'How it writes, per app. A line in a chat window and a paragraph in a document should not sound the same. Apps are matched on the name of the running program.'
    ) +
    `<div class="card">
      <div class="section-title">Rules<span class="spacer"></span><span class="tag">${rules.length}</span></div>
      <div class="rows">${rules
        .map((rule) =>
          editing === rule.id
            ? `<div class="row"><div class="grow">
                <input type="text" data-edit="name" value="${esc(rule.name)}" style="width:100%;margin-bottom:8px" />
                <input type="text" data-edit="processes" value="${esc(rule.processes.join(', '))}"
                  placeholder="slack, discord, teams" style="width:100%;margin-bottom:8px" />
                <textarea data-edit="instruction">${esc(rule.instruction)}</textarea>
                <div style="display:flex;gap:8px;margin-top:8px">
                  <button class="b primary" data-save="${rule.id}">Save</button>
                  <button class="b quiet" data-cancel="1">Cancel</button>
                </div>
              </div></div>`
            : `<div class="row" data-id="${rule.id}">
                <div class="grow">
                  <div class="text">${esc(rule.name)} ${
                    rule.builtIn ? '<span class="tag" style="margin-left:6px">built in</span>' : ''
                  }</div>
                  <div class="meta">${esc(rule.processes.join(', ')) || 'No apps yet'}</div>
                  <div class="meta">${esc(rule.instruction)}</div>
                </div>
                <div class="tools">
                  <button class="b sq" data-act="toggle" title="${rule.enabled ? 'Turn off' : 'Turn on'}" ${
                    rule.enabled ? 'style="color:var(--accent)"' : ''
                  }>${icon('check', 14)}</button>
                  <button class="b sq" data-act="edit" title="Edit">${icon('edit', 14)}</button>
                  ${
                    rule.builtIn
                      ? ''
                      : `<button class="b sq danger" data-act="delete" title="Delete">${icon('trash', 14)}</button>`
                  }
                </div>
              </div>`
        )
        .join('')}</div>
      <div class="adder">
        <input type="text" id="newRule" placeholder="Rule name, e.g. Jira tickets" />
        <button class="b primary" id="addRule">${icon('plus', 14)} Add</button>
      </div>
    </div>`
  );
}

// MARK: - Settings

function settingsScreen() {
  const settings = state.settings;
  const field = (label, hint, control) =>
    `<div class="field"><div><div class="label">${label}</div>${
      hint ? `<div class="hint">${hint}</div>` : ''
    }</div><div class="control">${control}</div></div>`;

  return (
    header('Settings', 'Everything is stored on this machine.') +
    `<div class="card">
      ${field(
        'Trigger key',
        'Hold it to talk, double-tap to lock recording on',
        `<button class="b" id="captureKey">${keyName(settings.triggerKeycode)}</button>`
      )}
      ${field(
        'Speech model',
        'Transcription runs on the processor unless you turn on NVIDIA acceleration, so smaller is quicker',
        `<select id="model">
          <option value="base.en"${settings.model === 'base.en' ? ' selected' : ''}>Base, fastest</option>
          <option value="small.en"${settings.model === 'small.en' ? ' selected' : ''}>Small, recommended</option>
          <option value="large-v3-turbo-q5_0"${
            settings.model === 'large-v3-turbo-q5_0' ? ' selected' : ''
          }>Large v3 Turbo, most accurate</option>
        </select>`
      )}
      ${field(
        'NVIDIA acceleration',
        'Downloads a 643MB CUDA build. Only worth it with an NVIDIA card; there is no Vulkan build for Windows, so AMD and Intel stay on the processor.',
        `<input type="checkbox" id="cuda"${settings.useCuda ? ' checked' : ''} />`
      )}
    </div>

    <div class="card">
      ${field(
        'Clean up with Groq',
        'The one thing that leaves this machine. Off means raw transcripts.',
        `<input type="checkbox" id="cleanup"${settings.cleanupEnabled ? ' checked' : ''} />`
      )}
      ${field(
        'Groq API key',
        'Stored as plain text in your app data folder. Anything running as you can read it.',
        `<input type="password" id="apiKey" placeholder="${
          state.hasKey ? 'Saved' : 'gsk_…'
        }" style="width:190px" />`
      )}
    </div>

    <div class="card">
      ${field(
        'Recording overlay',
        'Drops out of the top of the screen while you talk',
        `<input type="checkbox" id="overlay"${settings.showOverlay ? ' checked' : ''} />`
      )}
      ${field(
        'Sound when a take ends',
        '',
        `<input type="checkbox" id="sounds"${settings.playSounds ? ' checked' : ''} />`
      )}
    </div>

    <div class="card">
      ${field(
        'Your data',
        'Settings, history, vocabulary, snippets and the API key live here',
        `<button class="b" id="openFolder">${icon('folder', 14)} Open folder</button>`
      )}
      ${field('Quit FreeFlow', 'The trigger key stops working until you open it again',
        `<button class="b danger" id="quit">${icon('power', 14)} Quit</button>`)}
    </div>`
  );
}

// MARK: - Wiring

async function save(channel, value) {
  state = await window.freeflow.invoke(channel, value);
  editing = null;
  render();
}

function wire() {
  for (const button of main.querySelectorAll('[data-goto]')) {
    button.onclick = () => {
      screen = button.dataset.goto;
      render();
    };
  }

  const cancel = main.querySelector('[data-cancel]');
  if (cancel) {
    cancel.onclick = () => {
      editing = null;
      render();
    };
  }

  if (screen === 'history') wireHistory();
  if (screen === 'vocabulary') wireVocabulary();
  if (screen === 'snippets') wireSnippets();
  if (screen === 'actions') wireActions();
  if (screen === 'style') wireStyle();
  if (screen === 'settings') wireSettings();
}

function wireHistory() {
  const box = document.getElementById('search');
  if (box) {
    box.oninput = () => {
      search = box.value;
      render();
      const again = document.getElementById('search');
      again.focus();
      again.setSelectionRange(again.value.length, again.value.length);
    };
  }

  const clear = document.getElementById('clear');
  if (clear) {
    clear.onclick = () => save('history:update', state.history.filter((entry) => entry.pinned));
  }

  for (const button of main.querySelectorAll('.row [data-act]')) {
    button.onclick = async () => {
      const id = button.closest('.row').dataset.id;
      const entry = state.history.find((candidate) => candidate.id === id);
      if (!entry) return;

      if (button.dataset.act === 'copy') {
        await navigator.clipboard.writeText(entry.text);
        button.innerHTML = icon('check', 14);
        return;
      }
      const next =
        button.dataset.act === 'pin'
          ? state.history.map((candidate) =>
              candidate.id === id ? { ...candidate, pinned: !candidate.pinned } : candidate
            )
          : state.history.filter((candidate) => candidate.id !== id);
      await save('history:update', next);
    };
  }
}

function wireVocabulary() {
  const input = document.getElementById('newTerm');
  const add = () => {
    const term = input.value.trim();
    if (!term) return;
    void save('vocabulary:set', [...(state.vocabulary || []), term]);
  };
  document.getElementById('addTerm').onclick = add;
  input.onkeydown = (event) => {
    if (event.key === 'Enter') add();
  };
  input.focus();

  for (const button of main.querySelectorAll('[data-remove]')) {
    button.onclick = () =>
      save(
        'vocabulary:set',
        state.vocabulary.filter((_, index) => index !== Number(button.dataset.remove))
      );
  }
}

function wireSnippets() {
  const trigger = document.getElementById('newTrigger');
  const expansion = document.getElementById('newExpansion');
  document.getElementById('addSnippet').onclick = () => {
    if (!trigger.value.trim() || !expansion.value.trim()) return;
    void save('snippets:set', [
      ...(state.snippets || []),
      { id: uid(), trigger: trigger.value.trim(), expansion: expansion.value.trim(), enabled: true },
    ]);
  };

  const saveButton = main.querySelector('[data-save]');
  if (saveButton) {
    saveButton.onclick = () => {
      const id = saveButton.dataset.save;
      const next = state.snippets.map((item) =>
        item.id === id
          ? {
              ...item,
              trigger: main.querySelector('[data-edit="trigger"]').value.trim(),
              expansion: main.querySelector('[data-edit="expansion"]').value.trim(),
            }
          : item
      );
      void save('snippets:set', next);
    };
  }

  for (const button of main.querySelectorAll('.row [data-act]')) {
    button.onclick = () => {
      const id = button.closest('.row').dataset.id;
      if (button.dataset.act === 'edit') {
        editing = id;
        render();
        return;
      }
      const next =
        button.dataset.act === 'toggle'
          ? state.snippets.map((item) => (item.id === id ? { ...item, enabled: !item.enabled } : item))
          : state.snippets.filter((item) => item.id !== id);
      void save('snippets:set', next);
    };
  }
}

function wireActions() {
  document.getElementById('addAction').onclick = () => {
    const name = document.getElementById('newAction').value.trim();
    if (!name) return;
    void save('actions:set', [
      ...(state.actions || []),
      { id: uid(), name, icon: 'wand', prompt: `Rewrite this so that it ${name.toLowerCase()}.` },
    ]);
  };

  const saveButton = main.querySelector('[data-save]');
  if (saveButton) {
    saveButton.onclick = () => {
      const id = saveButton.dataset.save;
      const next = state.actions.map((item) =>
        item.id === id
          ? {
              ...item,
              name: main.querySelector('[data-edit="name"]').value.trim(),
              prompt: main.querySelector('[data-edit="prompt"]').value.trim(),
            }
          : item
      );
      void save('actions:set', next);
    };
  }

  for (const button of main.querySelectorAll('.row [data-act]')) {
    button.onclick = () => {
      const id = button.closest('.row').dataset.id;
      if (button.dataset.act === 'edit') {
        editing = id;
        render();
        return;
      }
      void save('actions:set', state.actions.filter((item) => item.id !== id));
    };
  }
}

function wireStyle() {
  document.getElementById('addRule').onclick = () => {
    const name = document.getElementById('newRule').value.trim();
    if (!name) return;
    void save('style:set', [
      ...(state.style || []),
      { id: uid(), name, processes: [], instruction: 'Write it plainly.', enabled: true, builtIn: false },
    ]);
  };

  const saveButton = main.querySelector('[data-save]');
  if (saveButton) {
    saveButton.onclick = () => {
      const id = saveButton.dataset.save;
      const next = state.style.map((rule) =>
        rule.id === id
          ? {
              ...rule,
              name: main.querySelector('[data-edit="name"]').value.trim(),
              processes: main
                .querySelector('[data-edit="processes"]')
                .value.split(',')
                .map((part) => part.trim())
                .filter(Boolean),
              instruction: main.querySelector('[data-edit="instruction"]').value.trim(),
            }
          : rule
      );
      void save('style:set', next);
    };
  }

  for (const button of main.querySelectorAll('.row [data-act]')) {
    button.onclick = () => {
      const id = button.closest('.row').dataset.id;
      if (button.dataset.act === 'edit') {
        editing = id;
        render();
        return;
      }
      const next =
        button.dataset.act === 'toggle'
          ? state.style.map((rule) => (rule.id === id ? { ...rule, enabled: !rule.enabled } : rule))
          : state.style.filter((rule) => rule.id !== id);
      void save('style:set', next);
    };
  }
}

function wireSettings() {
  const set = (changes) => save('settings:set', changes);

  document.getElementById('model').onchange = (event) => set({ model: event.target.value });
  document.getElementById('cuda').onchange = (event) => set({ useCuda: event.target.checked });
  document.getElementById('cleanup').onchange = (event) => set({ cleanupEnabled: event.target.checked });
  document.getElementById('overlay').onchange = (event) => set({ showOverlay: event.target.checked });
  document.getElementById('sounds').onchange = (event) => set({ playSounds: event.target.checked });
  document.getElementById('openFolder').onclick = () => window.freeflow.invoke('folder:open');
  document.getElementById('quit').onclick = () => window.freeflow.send('panel:quit');

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

// MARK: - Boot

window.freeflow.on('state', (next) => {
  state = next;
  render();
});

window.freeflow.on('theme', (theme) => {
  if (state) {
    state.theme = theme;
    render();
  }
});

window.freeflow.invoke('state:get').then((initial) => {
  state = initial;
  render();
});
