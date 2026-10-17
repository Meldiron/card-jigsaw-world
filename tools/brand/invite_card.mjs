// Draws the site's default link preview (web/invite-card.jpg) with the invite card's own code
// (functions/api/src/invite/card.js), and sample invite cards to look at (build/invite_cards/).
// Run by tools/brand/invite_card.py after it made the lettering; needs `npm install` in functions/api.
//
//   node tools/brand/invite_card.mjs [--samples-only]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderCard } from '../../functions/api/src/invite/card.js';
import { parseGrid } from '../../functions/api/src/invite/tiling.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const welcome = (name) => readFileSync(join(ROOT, 'assets', 'welcome', `${name}.jpg`));

if (!process.argv.includes('--samples-only')) {
  // The site's card: the red panda of the welcome pages, dealt as 3 x 3 cards, the middle card
  // lifted to swap with the last one (its face stays in view).
  const site = await renderCard({ image: welcome('red-panda'), board: parseGrid('cards-3x3'), kind: 'site', swaps: [[4, 8]] });
  const out = join(ROOT, 'web', 'invite-card.jpg');
  writeFileSync(out, site.jpeg);
  console.log(`${relative(ROOT, out)}: ${Math.round(site.jpeg.length / 1024)} KB`);
}

const samples = [
  ['red-panda', 'cards-7x7t7', false],
  ['tulip-fields', 'squares-5x5t4', false],
  ['parthenon', 'triangles-11x5t4', false],
  ['meerkat', 'hexagons-5x5t4', false],
  ['cherry-blossom', 'cards-3x3t0', true],
  ['island-lake', 'hexagons-7x7t7', true],
  ['emperor-penguins', 'cards-17x17t11', false],
  ['amsterdam-canal', 'triangles-37x18t11', false],
  ['azure-window', 'hexagons-23x23t11', false],
  ['california-rolls', 'squares-6x4t3', false],
  ['ammonoosuc-falls', 'triangles-7x3t0', false],
  ['water-lilies', 'hexagons-4x4t2', false],
];
const dir = join(ROOT, 'build', 'invite_cards');
mkdirSync(dir, { recursive: true });
for (const [name, grid, painting] of samples) {
  const t = performance.now();
  const card = await renderCard({ image: welcome(name), board: parseGrid(grid), painting });
  const file = join(dir, `${name}_${grid}${painting ? '_painting' : ''}.jpg`);
  writeFileSync(file, card.jpeg);
  console.log(`${relative(ROOT, file)}: ${card.cells} pieces, ${Math.round(card.jpeg.length / 1024)} KB, ${Math.round(performance.now() - t)} ms, dim ${card.dim.toFixed(2)}`);
}
