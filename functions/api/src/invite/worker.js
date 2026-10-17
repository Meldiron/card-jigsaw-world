// Draws one invite card off the function's main thread (store.js): the drawing takes a few seconds
// of the runtime's half CPU, and the other calls on this instance must not wait for it. On Linux
// the thread also takes the lowest priority (setpriority on a thread affects that thread only), so
// it draws with the time the calls leave over.
import { parentPort, workerData } from 'node:worker_threads';
import { setPriority } from 'node:os';
import { renderCard } from './card.js';

if (process.platform === 'linux' && workerData.nice !== false) {
  try {
    setPriority(19);
  } catch (_) {}
}
const { image, board, painting, seed } = workerData;
const card = renderCard({ image: Buffer.from(image), board, painting, seed });
parentPort.postMessage({ jpeg: card.jpeg, cells: card.cells });
