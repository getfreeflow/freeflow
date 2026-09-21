import { contextBridge, ipcRenderer } from 'electron';

/// The only bridge between the windows and the main process. Named channels only,
/// so a renderer can't reach anything that wasn't deliberately offered.

const RECEIVE = ['state', 'level', 'overlay:show', 'overlay:hide', 'panel:open', 'panel:close', 'audio:start', 'audio:stop'] as const;
const SEND = ['overlay:accept', 'overlay:discard', 'panel:hide', 'panel:quit', 'audio:chunk', 'audio:failed'] as const;
const INVOKE = ['state:get', 'settings:set', 'key:set', 'trigger:capture', 'history:update', 'folder:open'] as const;

type Receive = (typeof RECEIVE)[number];
type Send = (typeof SEND)[number];
type Invoke = (typeof INVOKE)[number];

contextBridge.exposeInMainWorld('freeflow', {
  on(channel: Receive, handler: (...args: unknown[]) => void): void {
    if (!RECEIVE.includes(channel)) return;
    ipcRenderer.on(channel, (_event, ...args) => handler(...args));
  },
  send(channel: Send, ...args: unknown[]): void {
    if (!SEND.includes(channel)) return;
    ipcRenderer.send(channel, ...args);
  },
  invoke(channel: Invoke, ...args: unknown[]): Promise<unknown> {
    if (!INVOKE.includes(channel)) return Promise.resolve(null);
    return ipcRenderer.invoke(channel, ...args);
  },
});
