import { Viewer } from 'molstar/lib/apps/viewer/app';
import { Color } from 'molstar/lib/mol-util/color';
import 'molstar/build/viewer/molstar.css';

export async function initViewer(): Promise<Viewer> {
  const host = document.getElementById('viewer');
  if (!host) {
    throw new Error('Viewer container not found.');
  }

  const viewer = await Viewer.create(host, {
    layoutShowControls: false,
    layoutShowSequence: false,
    layoutShowLog: false,
    layoutShowLeftPanel: false,
    viewportShowExpand: false,
  });

  viewer.plugin.canvas3d?.setProps({
    transparentBackground: false,
  });

  return viewer;
}
