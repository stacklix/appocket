export interface HTTPRequest {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
}
export interface HTTPResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}
type Bridge = { postMessage(message: unknown): Promise<unknown> };
declare global {
  interface Window {
    webkit?: { messageHandlers?: { appocket?: Bridge } };
    __appocketChunk?: (id: string, chunk: string) => void;
  }
}
export function createID(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}
const streams = new Map<string, (chunk: string) => void>();
if (typeof window !== 'undefined') window.__appocketChunk = (id, chunk) => streams.get(id)?.(chunk);
export const isNative = () => !!window.webkit?.messageHandlers?.appocket;
async function invoke<T>(method: string, params: unknown): Promise<T> {
  const bridge = window.webkit?.messageHandlers?.appocket;
  if (!bridge) throw new Error('原生宿主不可用');
  return (await bridge.postMessage({ version: 1, method, params })) as T;
}
export async function request(
  input: HTTPRequest,
  options: { signal?: AbortSignal; onChunk?: (chunk: string) => void } = {},
): Promise<HTTPResponse> {
  if (options.signal?.aborted) throw new DOMException('已取消', 'AbortError');
  const url = new URL(input.url);
  if (url.protocol !== 'https:' || url.username || url.password)
    throw new Error('接口必须使用 HTTPS');
  if (isNative()) {
    const id = createID();
    if (options.onChunk) streams.set(id, options.onChunk);
    const cancel = () => {
      void invoke('http.cancel', { id }).catch(() => {});
    };
    options.signal?.addEventListener('abort', cancel, { once: true });
    try {
      return await invoke<HTTPResponse>('http.request', {
        ...input,
        id,
        stream: !!options.onChunk,
      });
    } finally {
      streams.delete(id);
      options.signal?.removeEventListener('abort', cancel);
    }
  }
  const timeout = new AbortController();
  const abort = () => timeout.abort();
  options.signal?.addEventListener('abort', abort, { once: true });
  const timer = setTimeout(abort, 120000);
  try {
    const response = await fetch(input.url, {
      method: input.method ?? 'GET',
      headers: input.headers,
      body: input.body,
      signal: timeout.signal,
      redirect: 'error',
      credentials: 'omit',
    });
    let body = '';
    if (
      options.onChunk &&
      response.body &&
      response.headers.get('content-type')?.includes('text/event-stream')
    ) {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let size = 0;
      try {
        while (true) {
          const next = await reader.read();
          if (next.done) break;
          size += next.value.byteLength;
          if (size > 8 * 1024 * 1024) throw new Error('响应超过大小限制');
          const chunk = decoder.decode(next.value, { stream: true });
          options.onChunk(chunk);
        }
        const tail = decoder.decode();
        if (tail) options.onChunk(tail);
      } finally {
        await reader.cancel();
      }
    } else body = await response.text();
    return { status: response.status, headers: Object.fromEntries(response.headers), body };
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener('abort', abort);
  }
}
export const storage = {
  async get<T>(key: string): Promise<T | null> {
    const raw = isNative()
      ? await invoke<string | null>('state.get', { key })
      : localStorage.getItem(`sentra.${key}`);
    return raw === null ? null : (JSON.parse(raw) as T);
  },
  async set(key: string, value: unknown): Promise<void> {
    const encoded = JSON.stringify(value);
    if (isNative()) await invoke('state.set', { key, value: encoded });
    else localStorage.setItem(`sentra.${key}`, encoded);
  },
};
export async function authorizeOrigin(origin: string): Promise<void> {
  if (isNative()) await invoke('network.authorize', { origin: new URL(origin).origin });
}
export async function copyText(text: string): Promise<void> {
  if (isNative()) await invoke('clipboard.write', { text });
  else await navigator.clipboard.writeText(text);
}
export async function ready(): Promise<void> {
  if (isNative()) await invoke('runtime.ready', {});
}
