// Microphone capture, in a hidden window.
//
// Chromium already does the parts that are tedious in Node: picking the default
// input, resampling to 16 kHz, and surviving a device that changes mid-take. Asking
// for a 16 kHz mono AudioContext means the samples arrive in exactly the shape
// whisper.cpp wants.

let stream = null;
let context = null;
let source = null;
let processor = null;
let silent = null;

async function start() {
  if (processor) return;

  try {
    stream ??= await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });
  } catch (error) {
    // NotAllowedError means Windows privacy settings, NotFoundError means there is
    // no input device. Either way the take is over before it started.
    const message =
      error?.name === 'NotFoundError'
        ? 'No microphone found'
        : 'Windows is blocking the microphone. Settings, Privacy, Microphone.';
    window.freeflow.send('audio:failed', message);
    return;
  }

  context = new AudioContext({ sampleRate: 16000 });
  source = context.createMediaStreamSource(stream);
  // 1024 frames is 64ms at 16 kHz, which keeps the level meter lively.
  processor = context.createScriptProcessor(1024, 1, 1);

  processor.onaudioprocess = (event) => {
    const input = event.inputBuffer.getChannelData(0);
    // The buffer is reused between callbacks, so this has to be a copy.
    const samples = new Float32Array(input);

    let sum = 0;
    for (let index = 0; index < samples.length; index += 1) sum += samples[index] * samples[index];
    const level = Math.min(1, Math.sqrt(sum / samples.length) * 12);

    window.freeflow.send('audio:chunk', samples.buffer, level);
  };

  // A ScriptProcessor only runs when it's connected to something. Routing it
  // through a muted gain node keeps it running without playing the mic back.
  silent = context.createGain();
  silent.gain.value = 0;
  source.connect(processor);
  processor.connect(silent);
  silent.connect(context.destination);
}

function stop() {
  processor?.disconnect();
  source?.disconnect();
  silent?.disconnect();
  processor = null;
  source = null;
  silent = null;
  void context?.close();
  context = null;
  // The stream itself is kept open: re-acquiring it costs a few hundred
  // milliseconds, and that delay lands right where the first word goes.
}

window.freeflow.on('audio:start', start);
window.freeflow.on('audio:stop', stop);
