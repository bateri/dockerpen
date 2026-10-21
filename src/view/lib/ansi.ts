/**
 * The colours a program writes into its log with ANSI escapes (SGR), as spans the
 * view can paint with the terminal's own colours. Everything else an escape can do
 * is dropped.
 */

export interface Span {
  text: string;
  fg?: number;
  bg?: number;
  bold?: boolean;
  dim?: boolean;
  italic?: boolean;
  underline?: boolean;
}

const ESCAPE = /\x1b\[([0-9;]*)([A-Za-z])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-_]/g;

export function parseAnsi(input: string): Span[] {
  if (!input.includes("\x1b")) return [{ text: input }];
  const spans: Span[] = [];
  let style: Omit<Span, "text"> = {};
  let last = 0;
  for (const match of input.matchAll(ESCAPE)) {
    const at = match.index ?? 0;
    if (at > last) spans.push({ text: input.slice(last, at), ...style });
    last = at + match[0].length;
    if (match[2] !== "m") continue;
    const codes = (match[1] || "0").split(";").map(Number);
    for (let i = 0; i < codes.length; i += 1) {
      const code = codes[i]!;
      if (code === 0) style = {};
      else if (code === 1) style.bold = true;
      else if (code === 2) style.dim = true;
      else if (code === 3) style.italic = true;
      else if (code === 4) style.underline = true;
      else if (code === 22) {
        style.bold = false;
        style.dim = false;
      } else if (code === 23) style.italic = false;
      else if (code === 24) style.underline = false;
      else if (code >= 30 && code <= 37) style.fg = code - 30;
      else if (code >= 90 && code <= 97) style.fg = code - 90 + 8;
      else if (code === 39) delete style.fg;
      else if (code >= 40 && code <= 47) style.bg = code - 40;
      else if (code >= 100 && code <= 107) style.bg = code - 100 + 8;
      else if (code === 49) delete style.bg;
      else if ((code === 38 || code === 48) && codes[i + 1] === 5) {
        const value = codes[i + 2] ?? 0;
        // The 256-colour cube is folded onto the sixteen the theme has.
        const folded = value < 16 ? value : fold256(value);
        if (code === 38) style.fg = folded;
        else style.bg = folded;
        i += 2;
      } else if ((code === 38 || code === 48) && codes[i + 1] === 2) {
        i += 4;
      }
    }
  }
  if (last < input.length) spans.push({ text: input.slice(last), ...style });
  return spans.filter((span) => span.text !== "");
}

function fold256(value: number): number {
  if (value >= 232) return value > 243 ? 7 : 8;
  const v = value - 16;
  const r = Math.floor(v / 36);
  const g = Math.floor((v % 36) / 6);
  const b = v % 6;
  const bright = Math.max(r, g, b) > 3 ? 8 : 0;
  const index = (r > 2 ? 1 : 0) | (g > 2 ? 2 : 0) | (b > 2 ? 4 : 0);
  return (index === 0 && bright ? 8 : index) + (index === 0 ? 0 : bright);
}

/** Strips every escape, for searching and copying. */
export function stripAnsi(input: string): string {
  return input.includes("\x1b") ? input.replace(ESCAPE, "") : input;
}

/** A log line's level, when it says one in words: what a program without colours tells. */
export function levelOf(text: string): "error" | "warn" | "info" | "debug" | undefined {
  const head = text.slice(0, 160);
  if (
    /\b(ERROR|ERR|FATAL|PANIC|CRIT(ICAL)?|EMERG)\b|"level":"(error|fatal)"|level=(error|fatal)/i.test(
      head,
    )
  )
    return "error";
  if (/\b(WARN(ING)?)\b|"level":"warn|level=warn/i.test(head)) return "warn";
  if (/\b(DEBUG|TRACE)\b|"level":"(debug|trace)"|level=(debug|trace)/i.test(head)) return "debug";
  if (/\bINFO\b|"level":"info"|level=info/i.test(head)) return "info";
  return undefined;
}
