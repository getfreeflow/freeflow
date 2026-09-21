// Drives the real whisper.ts on a Windows runner, so a transcription failure
// shows its actual cause instead of "exited with 1".
//
// Run after `npm run build`:  node scripts/smoke-whisper.mjs

import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

const root = path.join(os.tmpdir(), 'freeflow-smoke');
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(root, { recursive: true });
process.env.FREEFLOW_DATA_DIR = root;

const whisper = await import('../dist/main/whisper.js');

function get(url, destination, redirects = 0) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': 'FreeFlow' } }, (response) => {
        const status = response.statusCode ?? 0;
        if (status >= 300 && status < 400 && response.headers.location) {
          if (redirects > 5) return reject(new Error('Too many redirects'));
          response.resume();
          return resolve(get(new URL(response.headers.location, url).toString(), destination, redirects + 1));
        }
        if (status !== 200) {
          response.resume();
          return reject(new Error(`HTTP ${status} for ${url}`));
        }
        const file = fs.createWriteStream(destination);
        response.pipe(file);
        file.on('finish', () => file.close(() => resolve()));
        file.on('error', reject);
      })
      .on('error', reject);
  });
}

/** Lists what actually landed on disk, which is how a missing DLL gets spotted. */
function tree(dir, depth = 0) {
  if (depth > 2 || !fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const size = entry.isDirectory() ? '' : `  ${(fs.statSync(full).size / 1024).toFixed(0)} KB`;
    console.log(`${'  '.repeat(depth + 1)}${entry.name}${entry.isDirectory() ? '/' : size}`);
    if (entry.isDirectory()) tree(full, depth + 1);
  }
}

let failed = false;

try {
  console.log('== preparing (base.en, CPU) ==');
  await whisper.prepare('base.en', false, (progress) => {
    if (progress.fraction === 0 || progress.stage === 'ready') {
      console.log(`   ${progress.stage}: ${progress.detail}`);
    }
  });
  console.log('   ready\n');

  console.log('== what was downloaded ==');
  tree(path.join(root, 'whisper'));
  tree(path.join(root, 'models'));
  console.log('');

  console.log('== fetching a known speech sample ==');
  const wav = path.join(root, 'jfk.wav');
  await get('https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/samples/jfk.wav', wav);
  console.log(`   ${(fs.statSync(wav).size / 1024).toFixed(0)} KB\n`);

  console.log('== transcribing ==');
  const text = await whisper.transcribe(wav);
  console.log(`   "${text}"\n`);

  if (!/ask not what your country/i.test(text)) {
    console.log('!! transcript does not match the sample');
    failed = true;
  } else {
    console.log('++ transcription works');
  }
} catch (error) {
  failed = true;
  console.log(`\n!! FAILED: ${error.message}\n`);

  // Run the executable by hand so its own diagnostics are visible even when the
  // app's wrapper swallowed them.
  const dir = path.join(root, 'whisper', 'cpu');
  if (fs.existsSync(dir)) {
    console.log('== what is on disk ==');
    tree(dir);

    const stack = [dir];
    let exe = null;
    while (stack.length && !exe) {
      const current = stack.pop();
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const full = path.join(current, entry.name);
        if (entry.isDirectory()) stack.push(full);
        else if (/^(whisper-cli|main)\.exe$/i.test(entry.name)) exe = full;
      }
    }

    if (exe) {
      console.log(`\n== running ${exe} --help directly ==`);
      const probe = spawnSync(exe, ['--help'], { encoding: 'utf8' });
      console.log(`   exit ${probe.status}`);
      if (probe.error) console.log(`   spawn error: ${probe.error.message}`);
      if (probe.stdout) console.log(probe.stdout.split('\n').slice(0, 8).join('\n'));
      if (probe.stderr) console.log(`   stderr: ${probe.stderr.slice(0, 1200)}`);
    } else {
      console.log('\n!! no whisper executable found in the extracted files');
    }
  }
}

process.exit(failed ? 1 : 0);
