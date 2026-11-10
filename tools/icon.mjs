// Draws dockerpen's icon, its mark (a sailing boat: its mast and its full sail are a D, and under
// them is the hull, a bow whose curve the foot of the sail follows), as PNGs, and writes them to
// src/assets/icon-<side>-<theme>.png. A terminal draws a program's icon only from the bytes it is
// given, so the program carries them (src/program/app.lua names the files); run this again after
// changing the shapes here.
//
//   node tools/icon.mjs
//
// It uses nothing but Node: the shapes are lines with round ends, a pixel is covered by as many of
// a grid of samples in it as lie within half a line's width of one, and the PNG is written by hand
// around zlib.

import { mkdirSync, writeFileSync } from "node:fs";
import { deflateSync, crc32 } from "node:zlib";

/** The width of every line, in the units of the mark's box: what a terminal draws its own marks in. */
const LINE = 1.35;

/** The point the hull and the foot of the sail are both drawn round, so that they run side by side. */
const CENTRE = [6, 3.15];

/** The point of the circle of this radius round the centre that is under `x`. */
const under = (radius, x) => [x, CENTRE[1] + Math.sqrt(radius ** 2 - (x - CENTRE[0]) ** 2)];

const HULL = 7.4;
const FOOT = 4.8;

/**
 * The mark in its 12-unit box, the grid a terminal draws its own marks on: each line's opacity and
 * its runs. A run is a point and the steps from it, each a point (a straight line to it), two
 * control points and a point (a cubic curve to it), or the word "round" and a point (the shorter
 * arc to it of the circle round the centre).
 */
const MARK = [
  // The sail: from the head of the mast out and down as a sail full of wind, round its lower
  // corner, along its foot and up the mast again.
  {
    opacity: 1,
    runs: [
      [
        [4.2, 1.6],
        [7.4, 1.9, 9.8, 3.5, 9.8, 5.2],
        [9.8, 6.2, 9.27, 6.75, ...under(FOOT, 8.6)],
        ["round", ...under(FOOT, 4.2)],
        [4.2, 1.6],
      ],
    ],
  },
  // The hull.
  {
    opacity: 0.65,
    runs: [[under(HULL, 1.6), ["round", ...under(HULL, 10.4)]]],
  },
];

/**
 * The part of that box an icon shows: all of it. A terminal draws the picture in the square its
 * own marks take, so the mark is as large beside them as it is in its box.
 */
const FRAME = { x: 0, y: 0, side: 12 };

/** One colour for each ground, as an icon's `theme` says: the ground the icon is made to stand on. */
const COLOURS = {
  dark: [0x6c, 0xa8, 0xf5],
  light: [0x1f, 0x5f, 0xc9],
};

/** 32 pixels is what a terminal's strip asks for on a Retina screen; 64 for those that draw larger. */
const SIDES = [32, 64];

const SAMPLES = 8;

/** Into how many straight pieces a curve is cut. */
const CUTS = 24;

/** The straight pieces of a run, each as its two ends. */
function pieces([start, ...steps]) {
  const out = [];
  let [x, y] = start;
  for (const step of steps) {
    if (step.length === 2) {
      out.push([x, y, step[0], step[1]]);
      [x, y] = step;
      continue;
    }
    // Where the curve is at each cut of it, from 0 at its start to 1 at its end.
    let at;
    let end;
    if (step[0] === "round") {
      end = [step[1], step[2]];
      const [cx, cy] = CENTRE;
      const radius = Math.hypot(x - cx, y - cy);
      const from = Math.atan2(y - cy, x - cx);
      let turn = Math.atan2(end[1] - cy, end[0] - cx) - from;
      if (turn > Math.PI) turn -= 2 * Math.PI;
      if (turn < -Math.PI) turn += 2 * Math.PI;
      at = (t) => [cx + radius * Math.cos(from + t * turn), cy + radius * Math.sin(from + t * turn)];
    } else {
      const [ax, ay, bx, by, ex, ey] = step;
      const [sx, sy] = [x, y];
      end = [ex, ey];
      at = (t) => {
        const u = 1 - t;
        return [
          u * u * u * sx + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * ex,
          u * u * u * sy + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * ey,
        ];
      };
    }
    let [px, py] = [x, y];
    for (let cut = 1; cut <= CUTS; cut++) {
      const [qx, qy] = at(cut / CUTS);
      out.push([px, py, qx, qy]);
      [px, py] = [qx, qy];
    }
    [x, y] = end;
  }
  return out;
}

const LINES = MARK.map(({ opacity, runs }) => ({ opacity, pieces: runs.flatMap(pieces) }));

/** Whether a point lies on a line: within half the line's width of one of its pieces. */
function inside(px, py, line) {
  const reach = (LINE / 2) ** 2;
  for (const [ax, ay, bx, by] of line.pieces) {
    const [dx, dy] = [bx - ax, by - ay];
    const length = dx * dx + dy * dy;
    const along =
      length === 0 ? 0 : Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / length));
    const [ox, oy] = [px - (ax + along * dx), py - (ay + along * dy)];
    if (ox * ox + oy * oy <= reach) return true;
  }
  return false;
}

function draw(side, [red, green, blue]) {
  const scale = FRAME.side / side;
  const rows = [];
  for (let row = 0; row < side; row++) {
    const line = Buffer.alloc(1 + side * 4); // a leading 0: no filter
    for (let column = 0; column < side; column++) {
      // The lines are drawn one over another, each with its opacity.
      let alpha = 0;
      for (const shape of LINES) {
        let hits = 0;
        for (let sy = 0; sy < SAMPLES; sy++) {
          for (let sx = 0; sx < SAMPLES; sx++) {
            const px = FRAME.x + (column + (sx + 0.5) / SAMPLES) * scale;
            const py = FRAME.y + (row + (sy + 0.5) / SAMPLES) * scale;
            if (inside(px, py, shape)) hits++;
          }
        }
        const cover = (hits / (SAMPLES * SAMPLES)) * shape.opacity;
        alpha = cover + alpha * (1 - cover);
      }
      line.set([red, green, blue, Math.round(alpha * 255)], 1 + column * 4);
    }
    rows.push(line);
  }
  return png(side, Buffer.concat(rows));
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

function png(side, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(side, 0);
  header.writeUInt32BE(side, 4);
  header.set([8, 6, 0, 0, 0], 8); // 8 bits, RGBA, deflate, no filter method, no interlace
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(pixels, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const directory = new URL("../src/assets/", import.meta.url);
mkdirSync(directory, { recursive: true });
let written = 0;
for (const [theme, colour] of Object.entries(COLOURS)) {
  for (const side of SIDES) {
    writeFileSync(new URL(`icon-${side}-${theme}.png`, directory), draw(side, colour));
    written += 1;
  }
}
console.log(`wrote ${written} icons to src/assets/`);
