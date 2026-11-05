// Draws dockerpen's icon, a white shipping container on a blue tile, as PNGs, and writes them to
// src/assets/icon-<side>-<theme>.png.
// A terminal draws a program's icon only from the bytes it is given, so the program carries them
// (src/program/app.lua names the files); run this again after changing the shapes here.
//
//   node tools/icon.mjs
//
// It is made to be read at the 16 points a terminal's strip draws it at: few parts, nothing
// thinner than 2 units, and the tile filling the square.
//
// It uses nothing but Node: the tile and the mark are each a list of layers of simple shapes on a
// 32-unit grid (the side of the smaller icon, so that an edge on a whole unit is a whole pixel at 32
// and at 64), each layer painted with an opacity or cut out of what is under it. A pixel's coverage
// is taken from a grid of samples in it, and the PNG is written by hand around zlib.

import { mkdirSync, writeFileSync } from "node:fs";
import { deflateSync, crc32 } from "node:zlib";
import { fileURLToPath } from "node:url";

/** The side of the grid the shapes are drawn on. */
export const GRID = 32;

/** The tile the mark stands on, and its blue, from the top of it to the bottom. */
const TILE = [{ paint: { rect: [1, 1, 30, 30, 7] } }];
const TOP = [0x4f, 0x93, 0xf6];
const BOTTOM = [0x1a, 0x52, 0xc4];

/** The mark, in white on the tile: a container, its three ribs cut out. */
export const MARK = [
  { paint: { rect: [6, 9, 20, 14, 3] } },
  { cut: { any: [10, 15, 20].map((x) => ({ rect: [x, 12, 2, 8] })) } },
];

/** The grounds an icon's `theme` names. The tile stands on either, so each gets the same picture. */
const THEMES = ["dark", "light"];

/** 32 pixels is what a terminal's strip asks for on a Retina screen; 64 for those that draw larger. */
const SIDES = [32, 64];

// The shapes. Each is an object with one of these keys:
//   rect:   [x, y, width, height, corner radius]
//   circle: [cx, cy, radius]
//   stroke: [[x, y], ...], a line through the points with round ends and joins, `width` wide
//   poly:   [[x, y], ...], the polygon through the points
//   all / any: [shape, ...], what is in every one of them / in any of them
//   not:    shape, what is outside it

/** Whether the point (x, y) of the grid is in the shape. */
export function inside(shape, x, y) {
  if (shape.rect) {
    const [rx, ry, w, h, r = 0] = shape.rect;
    const dx = Math.max(Math.abs(x - (rx + w / 2)) - (w / 2 - r), 0);
    const dy = Math.max(Math.abs(y - (ry + h / 2)) - (h / 2 - r), 0);
    return dx * dx + dy * dy <= r * r;
  }
  if (shape.circle) {
    const [cx, cy, r] = shape.circle;
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
  }
  if (shape.stroke) {
    const half = shape.width / 2;
    const points = shape.stroke;
    if (!near(shape, points, half, x, y)) return false;
    for (let i = 0; i < points.length - 1; i++) {
      if (segment(x, y, points[i], points[i + 1]) <= half) return true;
    }
    return points.length === 1 && segment(x, y, points[0], points[0]) <= half;
  }
  if (shape.poly) {
    let odd = false;
    const points = shape.poly;
    if (!near(shape, points, 0, x, y)) return false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
      const [xi, yi] = points[i];
      const [xj, yj] = points[j];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) odd = !odd;
    }
    return odd;
  }
  if (shape.all) return shape.all.every((part) => inside(part, x, y));
  if (shape.any) return shape.any.some((part) => inside(part, x, y));
  if (shape.not) return !inside(shape.not, x, y);
  throw new Error(`a shape with none of the known keys: ${JSON.stringify(shape)}`);
}

const BOUNDS = new WeakMap();

/** Whether (x, y) is in the box around the points, `pad` larger on each side: a quick no. */
function near(shape, points, pad, x, y) {
  let box = BOUNDS.get(shape);
  if (!box) {
    const xs = points.map((p) => p[0]);
    const ys = points.map((p) => p[1]);
    box = [Math.min(...xs) - pad, Math.min(...ys) - pad, Math.max(...xs) + pad, Math.max(...ys) + pad];
    BOUNDS.set(shape, box);
  }
  return x >= box[0] && y >= box[1] && x <= box[2] && y <= box[3];
}

/** The distance from (x, y) to the segment from a to b. */
function segment(x, y, [ax, ay], [bx, by]) {
  const vx = bx - ax;
  const vy = by - ay;
  const length = vx * vx + vy * vy;
  const t = length === 0 ? 0 : Math.min(Math.max(((x - ax) * vx + (y - ay) * vy) / length, 0), 1);
  return Math.hypot(x - (ax + t * vx), y - (ay + t * vy));
}

/** The opacity of the mark at a point: its layers, each painted over or cut out of the ones before. */
function opacity(mark, x, y) {
  let alpha = 0;
  for (const layer of mark) {
    if (layer.cut) {
      if (inside(layer.cut, x, y)) alpha = 0;
    } else if (inside(layer.paint, x, y)) {
      const a = layer.alpha ?? 1;
      alpha = a + alpha * (1 - a);
    }
  }
  return alpha;
}

/**
 * The coverage of the mark in each pixel of a square `side` pixels wide, row by row. `scale`
 * draws the mark smaller (below 1) about the middle of the grid.
 */
export function coverage(mark, side, { samples = 8, scale = 1 } = {}) {
  const out = new Float64Array(side * side);
  const unit = GRID / side;
  for (let row = 0; row < side; row++) {
    for (let column = 0; column < side; column++) {
      let sum = 0;
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          const x = GRID / 2 + ((column + (sx + 0.5) / samples) * unit - GRID / 2) / scale;
          const y = GRID / 2 + ((row + (sy + 0.5) / samples) * unit - GRID / 2) / scale;
          sum += opacity(mark, x, y);
        }
      }
      out[row * side + column] = sum / (samples * samples);
    }
  }
  return out;
}

/** The mark in white on the tile, as a PNG. */
export function draw(mark, side) {
  const ground = coverage(TILE, side);
  const ink = coverage(mark, side);
  const pixels = Buffer.alloc(side * side * 4);
  for (let i = 0; i < side * side; i++) {
    const down = Math.floor(i / side) / (side - 1);
    const blue = TOP.map((c, k) => c + (BOTTOM[k] - c) * down);
    const rgb = blue.map((c) => Math.round(255 * ink[i] + c * (1 - ink[i])));
    pixels.set([...rgb, Math.round(ground[i] * 255)], i * 4);
  }
  return png(side, pixels);
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** A PNG of a square of RGBA pixels, row by row. */
export function png(side, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(side, 0);
  header.writeUInt32BE(side, 4);
  header.set([8, 6, 0, 0, 0], 8); // 8 bits, RGBA, deflate, no filter method, no interlace
  const rows = [];
  for (let row = 0; row < side; row++) {
    rows.push(Buffer.from([0]), pixels.subarray(row * side * 4, (row + 1) * side * 4)); // no filter
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.concat(rows), { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// Run as a script (not imported to draw other marks), it writes the icons the program carries.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const directory = new URL("../src/assets/", import.meta.url);
  mkdirSync(directory, { recursive: true });
  let written = 0;
  for (const theme of THEMES) {
    for (const side of SIDES) {
      writeFileSync(new URL(`icon-${side}-${theme}.png`, directory), draw(MARK, side));
      written += 1;
    }
  }
  console.log(`wrote ${written} icons to src/assets/`);
}
