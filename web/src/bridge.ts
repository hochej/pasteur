import type { Viewer } from 'molstar/lib/apps/viewer/app';
import { normalizeFormat } from './formats';

declare global {
  interface Window {
    Pasteur?: {
      loadFromNative: (payload: LoadRequest) => void;
      clearFromNative: () => void;
      exportFromNative: (payload: ExportRequest) => void;
      configureFromNative: (payload: UIConfig) => void;
    };
    webkit?: {
      messageHandlers?: {
        pasteur?: {
          postMessage: (message: Record<string, unknown>) => void;
        };
      };
    };
  }
}

type LoadRequest = {
  id: string;
  format: string;
  data: string;
  options?: Record<string, string> | null;
};

type ExportRequest = {
  id: string;
  targetFormat: string;
};

type UIConfig = {
  hud: {
    visible: boolean;
    compact: boolean;
    showStatus: boolean;
    buttons: string[];
  };
  overlayDelayMs: number;
  hideMolstarUi: boolean;
  panelAlpha: number;
};

let lastInput = '';
let lastLoadId = '';
let overlayDelayMs = 200;
let history: Array<{ format: string; data: string }> = [];
let historyIndex = -1;
const defaultConfig: UIConfig = {
  hud: {
    visible: true,
    compact: true,
    showStatus: false,
    buttons: []
  },
  overlayDelayMs: 200,
  hideMolstarUi: true,
  panelAlpha: 0.7
};

export function initBridge(viewer: Viewer) {
  const overlay = document.getElementById('overlay');
  const overlayTitle = document.getElementById('overlay-title');
  const overlayMessage = document.getElementById('overlay-message');
  const status = document.getElementById('status');

  const setStatus = (text: string) => {
    if (status) {
      status.textContent = text;
    }
  };

  const showOverlay = (title: string, message = '') => {
    if (!overlay || !overlayTitle || !overlayMessage) {
      return;
    }
    overlayTitle.textContent = title;
    overlayMessage.textContent = message;
    overlay.classList.remove('hidden');
  };

  const hideOverlay = () => {
    if (overlay) {
      overlay.classList.add('hidden');
    }
  };

  const post = (message: Record<string, unknown>) => {
    window.webkit?.messageHandlers?.pasteur?.postMessage(message);
  };

  const bridgeAvailable = !!window.webkit?.messageHandlers?.pasteur?.postMessage;
  if (!bridgeAvailable) {
    console.warn('Native bridge is not available. Messages will be dropped.');
    setStatus('Native bridge unavailable');
  }

  applyHudConfig(defaultConfig);

  const updateNav = () => {
    const backButton = document.getElementById('back-btn') as HTMLButtonElement | null;
    const forwardButton = document.getElementById('forward-btn') as HTMLButtonElement | null;
    if (backButton) {
      backButton.disabled = historyIndex <= 0;
    }
    if (forwardButton) {
      forwardButton.disabled = historyIndex < 0 || historyIndex >= history.length - 1;
    }
  };

  const pushHistory = (format: string, data: string) => {
    history = history.slice(0, historyIndex + 1);
    history.push({ format, data });
    if (history.length > 10) {
      history.shift();
    }
    historyIndex = history.length - 1;
    updateNav();
  };

  const loadStructure = async (format: string, data: string, fromHistory: boolean) => {
    let overlayTimer: number | undefined;
    overlayTimer = window.setTimeout(() => {
      showOverlay('Loading...');
      setStatus(`Loading ${format.toUpperCase()}`);
    }, overlayDelayMs);

    let timeoutHandle: number | undefined;
    const timeoutPromise = new Promise<never>((_, reject) => {
      timeoutHandle = window.setTimeout(() => {
        reject(new Error('Load timed out after 12 seconds.'));
      }, 12000);
    });
    const clearTimers = () => {
      if (overlayTimer !== undefined) {
        window.clearTimeout(overlayTimer);
        overlayTimer = undefined;
      }
      if (timeoutHandle !== undefined) {
        window.clearTimeout(timeoutHandle);
        timeoutHandle = undefined;
      }
    };

    try {
      await viewer.plugin.clear();
      console.log('Viewer cleared, starting load.');
      await Promise.race([
        viewer.loadStructureFromData(data, format),
        timeoutPromise
      ]);
      clearTimers();
      hideOverlay();
      setStatus(`${format.toUpperCase()} loaded`);
      if (!fromHistory) {
        pushHistory(format, data);
      }
    } catch (error) {
      clearTimers();
      const message = error instanceof Error ? error.message : String(error);
      console.error('Load failed', message);
      showOverlay('Parse error', message);
      setStatus('Load failed');
      throw error;
    }
  };

  const loadHistoryAt = async (index: number) => {
    if (index < 0 || index >= history.length) {
      return;
    }
    historyIndex = index;
    updateNav();
    const entry = history[index];
    await loadStructure(entry.format, entry.data, true);
  };

  const forwardConsole = () => {
    const originalLog = console.log;
    const originalWarn = console.warn;
    const originalError = console.error;

    const send = (level: string, args: unknown[]) => {
      const text = args.map((arg) => {
        if (typeof arg === 'string') return arg;
        try {
          return JSON.stringify(arg);
        } catch {
          return String(arg);
        }
      }).join(' ');
      post({ type: 'log', level, message: text });
    };

    console.log = (...args: unknown[]) => {
      originalLog(...args);
      send('log', args);
    };
    console.warn = (...args: unknown[]) => {
      originalWarn(...args);
      send('warn', args);
    };
    console.error = (...args: unknown[]) => {
      originalError(...args);
      send('error', args);
    };
  };

  forwardConsole();

  const exportSession = async (id: string) => {
    try {
      const blob = await viewer.plugin.managers.snapshot.serialize({ type: 'molx' });
      const data = await blobToBase64(blob);
      post({ type: 'exportResult', id, data });
      setStatus('Session exported');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      post({ type: 'error', id, message });
      showOverlay('Export failed', message);
    }
  };

  window.Pasteur = {
    loadFromNative: async (payload: LoadRequest) => {
      const format = normalizeFormat(payload.format);
      lastInput = payload.data;
      lastLoadId = payload.id;

      console.log('Load requested', { id: payload.id, format, bytes: payload.data.length });

      try {
        await loadStructure(format, payload.data, false);
        post({ type: 'loaded', id: payload.id, stats: {} });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        post({ type: 'error', id: payload.id, message });
      }
    },
    clearFromNative: async () => {
      await viewer.plugin.clear();
      setStatus('Cleared');
    },
    exportFromNative: async (payload: ExportRequest) => {
      await exportSession(payload.id);
    },
    configureFromNative: (payload: UIConfig) => {
      overlayDelayMs = payload.overlayDelayMs ?? overlayDelayMs;
      applyHudConfig({ ...defaultConfig, ...payload, hud: { ...defaultConfig.hud, ...payload.hud } });
    }
  };

  post({ type: 'ready' });
  setStatus('Pasteur ready');
  updateNav();

  const backButton = document.getElementById('back-btn');
  backButton?.addEventListener('click', async () => {
    await loadHistoryAt(historyIndex - 1);
  });

  const forwardButton = document.getElementById('forward-btn');
  forwardButton?.addEventListener('click', async () => {
    await loadHistoryAt(historyIndex + 1);
  });

  const screenshotButton = document.getElementById('screenshot-btn');
  screenshotButton?.addEventListener('click', async () => {
    try {
      document.body.classList.add('capture');
      await new Promise(requestAnimationFrame);
      await new Promise(requestAnimationFrame);
      const helper = viewer.plugin.helpers?.viewportScreenshot;
      if (!helper) {
        throw new Error('Screenshot helper unavailable.');
      }
      const dataUri = await helper.getImageDataUri();
      const base64 = dataUri.split(',')[1];
      if (!base64) {
        throw new Error('Failed to encode screenshot.');
      }
      post({ type: 'screenshotResult', data: base64 });
      setStatus('Screenshot saved');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error('Screenshot failed', message);
      showOverlay('Screenshot failed', message);
    } finally {
      document.body.classList.remove('capture');
    }
  });
}

function applyHudConfig(config: UIConfig) {
  const hud = document.getElementById('hud');
  const status = document.getElementById('status');

  if (hud) {
    hud.classList.toggle('compact', config.hud.compact);
    hud.classList.toggle('hidden', !config.hud.visible);
  }
  if (status) {
    status.classList.toggle('hidden', !config.hud.showStatus);
  }

  document.body.classList.toggle('molstar-ui-hidden', config.hideMolstarUi);
  document.documentElement.style.setProperty('--panel-alpha', String(config.panelAlpha));
}

async function blobToBase64(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
