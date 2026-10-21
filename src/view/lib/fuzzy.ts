/**
 * Fuzzy matching for the palette and the filters: every character of the query, in
 * order, somewhere in the text, scored so that matches at word starts and in a run
 * come first.
 */

export interface Match {
  score: number;
  /** The indices of the matched characters, for highlighting. */
  positions: number[];
}

export function fuzzy(query: string, text: string): Match | undefined {
  const q = query.trim().toLowerCase();
  if (q === "") return { score: 0, positions: [] };
  const t = text.toLowerCase();
  const direct = t.indexOf(q);
  if (direct >= 0) {
    const positions = Array.from({ length: q.length }, (_, i) => direct + i);
    const start = direct === 0 || /[\s\-_./:]/.test(t[direct - 1] ?? "") ? 30 : 0;
    return { score: 100 + start - direct * 0.5 - t.length * 0.05, positions };
  }
  const positions: number[] = [];
  let score = 0;
  let run = 0;
  let from = 0;
  for (const char of q) {
    if (char === " ") continue;
    const at = t.indexOf(char, from);
    if (at < 0) return undefined;
    const boundary = at === 0 || /[\s\-_./:]/.test(t[at - 1] ?? "");
    run = positions.length > 0 && positions.at(-1) === at - 1 ? run + 1 : 0;
    score += 1 + run * 2 + (boundary ? 4 : 0) - (at - from) * 0.1;
    positions.push(at);
    from = at + 1;
  }
  // Characters scattered over the whole text are a coincidence, not a match.
  const span = positions.at(-1)! - positions[0]! + 1;
  if (span > Math.max(positions.length * 3, positions.length + 4)) return undefined;
  return { score: score - t.length * 0.05, positions };
}
