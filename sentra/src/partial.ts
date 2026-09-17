// Display-only tolerant JSON reader. Never persist or validate a partial result.
export function partialResult(source: string): Record<string, any> {
  let i = source.indexOf('{');
  if (i < 0) return {};
  const ws = () => {
    while (/\s/.test(source[i] ?? '') && i < source.length) i++;
  };
  const string = (): string => {
    i++;
    let raw = '';
    while (i < source.length) {
      const c = source[i++];
      if (c === '"') break;
      if (c === '\\') {
        const width = source[i] === 'u' ? 5 : 1;
        if (i + width > source.length) break;
        raw += c + source.slice(i, i + width);
        i += width;
      } else raw += c;
    }
    try {
      return JSON.parse(`"${raw}"`);
    } catch {
      return '';
    }
  };
  const read = (depth = 0): any => {
    ws();
    if (i >= source.length || depth > 40) return undefined;
    const c = source[i];
    if (c === '"') return string();
    if (c === '{') {
      i++;
      const o: Record<string, any> = {};
      while (i < source.length) {
        ws();
        if (source[i] !== '"') break;
        const key = string();
        ws();
        if (source[i++] !== ':') break;
        const value = read(depth + 1);
        if (value !== undefined && !['__proto__', 'constructor', 'prototype'].includes(key))
          o[key] = value;
        ws();
        if (source[i] !== ',') break;
        i++;
      }
      if (source[i] === '}') i++;
      return o;
    }
    if (c === '[') {
      i++;
      const a = [];
      while (i < source.length) {
        ws();
        if (source[i] === ']') break;
        const start = i;
        const v = read(depth + 1);
        if (v !== undefined) a.push(v);
        if (i === start) break;
        ws();
        if (source[i] !== ',') break;
        i++;
      }
      if (source[i] === ']') i++;
      return a;
    }
    const start = i;
    while (i < source.length && !/[,\]}\s]/.test(source[i])) i++;
    try {
      return JSON.parse(source.slice(start, i));
    } catch {
      return undefined;
    }
  };
  return read() ?? {};
}
