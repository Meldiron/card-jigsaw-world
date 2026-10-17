// Draws one invite card off the function's main thread (store.js): the drawing takes a second or
// two of the runtime's half CPU, and the other calls on this instance must not wait for it.
import { parentPort, workerData } from 'node:worker_threads';
import { renderCard } from './card.js';

const { image, board, painting, seed } = workerData;
const card = renderCard({ image: Buffer.from(image), board, painting, seed });
parentPort.postMessage({ jpeg: card.jpeg, cells: card.cells });
