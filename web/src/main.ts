import './styles.css';
import { initViewer } from './viewer';
import { initBridge } from './bridge';

async function boot() {
  try {
    const viewer = await initViewer();
    initBridge(viewer);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const overlay = document.getElementById('overlay');
    const title = document.getElementById('overlay-title');
    const detail = document.getElementById('overlay-message');

    if (overlay && title && detail) {
      overlay.classList.remove('hidden');
      title.textContent = 'Viewer failed to start';
      detail.textContent = message;
    }
  }
}

void boot();
