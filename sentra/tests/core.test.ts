import { describe, it, expect, vi, beforeEach } from 'vitest';
import { endpoint, defaults, validateResult } from '../src/models';
import { SSEParser, analyze } from '../src/api';
import { partialResult } from '../src/partial';
import { request, storage } from '@appocket/host-sdk';
const valid = {
  source_language: '中文',
  translation_language: '英语',
  translations: [
    { text: 'Hello', type: 'direct' },
    { text: 'Hi', type: 'natural' },
  ],
  notes: ['Note'],
};
beforeEach(() => {
  localStorage.clear();
  delete window.webkit;
  vi.unstubAllGlobals();
});
describe('provider contracts', () => {
  it('normalizes endpoints and rejects unsafe URLs', () => {
    expect(endpoint({ ...defaults, baseUrl: 'https://provider.test/v1/' })).toBe(
      'https://provider.test/v1/chat/completions',
    );
    expect(endpoint({ ...defaults, protocol: 'anthropic', baseUrl: 'https://provider.test' })).toBe(
      'https://provider.test/v1/messages',
    );
    for (const baseUrl of [
      'http://provider.test',
      'https://user:pass@provider.test',
      'https://provider.test?token=x',
      'https://provider.test/messages',
    ])
      expect(() => endpoint({ ...defaults, baseUrl })).toThrow();
  });
  it('requires translation direction and both variants', () => {
    expect(validateResult('translate', JSON.stringify(valid), '你好', '英语')).toEqual(valid);
    expect(() =>
      validateResult(
        'translate',
        JSON.stringify({ ...valid, translation_language: '日语' }),
        '你好',
        '英语',
      ),
    ).toThrow();
    expect(() =>
      validateResult('translate', JSON.stringify({ ...valid, translations: [] }), '你好', '英语'),
    ).toThrow();
  });
  it('rejects analysis of a rewritten sentence and contradictory corrections', () => {
    const grammar = {
      source_language: 'en',
      analysis_text: 'He go.',
      analysis_origin: 'original',
      correct: false,
      summary: 'agreement',
      corrections: [{ original: 'go', corrected: 'goes', explanation: 'agreement' }],
      structure: [{ text: 'He', part: 'pronoun', role: 'subject' }],
      grammar_points: [],
    };
    expect(validateResult('grammar', JSON.stringify(grammar), 'He go.', '英语')).toEqual(grammar);
    expect(() =>
      validateResult('grammar', JSON.stringify({ ...grammar, correct: true }), 'He go.', '英语'),
    ).toThrow();
    expect(() => validateResult('grammar', JSON.stringify(grammar), 'He goes.', '英语')).toThrow();
  });
});
describe('streaming', () => {
  it('handles arbitrary boundaries, CRLF, comments and multiline data', () => {
    const values: string[] = [];
    const parser = new SSEParser((x) => values.push(x));
    for (const char of ':ping\r\ndata: one\r\ndata: two\r\n\r\ndata: [DONE]') parser.feed(char);
    parser.finish();
    expect(values).toEqual(['one\ntwo', '[DONE]']);
  });
  it('renders incomplete JSON without saving it', () => {
    expect(partialResult('{"translations":[{"text":"Hello')).toEqual({
      translations: [{ text: 'Hello' }],
    });
  });
  it('consumes streamed OpenAI chunks and rejects interrupted responses', async () => {
    const body = JSON.stringify(valid);
    let complete = true;
    vi.stubGlobal(
      'fetch',
      vi.fn(
        async () =>
          new Response(
            `data: ${JSON.stringify({ choices: [{ delta: { content: body } }] })}\n\n${complete ? 'data: [DONE]\n\n' : ''}`,
            { headers: { 'content-type': 'text/event-stream' } },
          ),
      ),
    );
    const config = { ...defaults, baseUrl: 'https://test.example/v1', model: 'test' };
    const progress = vi.fn();
    const result = await analyze(
      'translate',
      '你好',
      config,
      new AbortController().signal,
      progress,
    );
    expect(result.data).toEqual(valid);
    expect(progress).toHaveBeenCalledWith(body);
    complete = false;
    await expect(
      analyze('translate', '你好', config, new AbortController().signal, progress),
    ).rejects.toThrow('连接中断');
  });
  it('accepts Anthropic and non-streaming compatible responses', async () => {
    const content = JSON.stringify(valid);
    vi.stubGlobal(
      'fetch',
      vi.fn(
        async () =>
          new Response(
            JSON.stringify({ content: [{ type: 'text', text: content }], stop_reason: 'end_turn' }),
            { headers: { 'content-type': 'application/json' } },
          ),
      ),
    );
    expect(
      (
        await analyze(
          'translate',
          '你好',
          { ...defaults, protocol: 'anthropic', baseUrl: 'https://test.example', model: 'test' },
          new AbortController().signal,
          () => {},
        )
      ).data,
    ).toEqual(valid);
  });
});
describe('host SDK', () => {
  it('routes requests to the native bridge without calling fetch', async () => {
    const postMessage = vi.fn(async () => ({ status: 200, headers: {}, body: 'ok' }));
    window.webkit = { messageHandlers: { appocket: { postMessage } } };
    const fetch = vi.fn();
    vi.stubGlobal('fetch', fetch);
    expect((await request({ url: 'https://first.example/path' })).body).toBe('ok');
    await request({ url: 'https://second.example/path' });
    expect(fetch).not.toHaveBeenCalled();
    expect(postMessage.mock.calls).toHaveLength(2);
  });
  it('aborts without sending pre-cancelled requests', async () => {
    const abort = new AbortController();
    abort.abort();
    await expect(request({ url: 'https://a.example' }, { signal: abort.signal })).rejects.toThrow();
  });
  it('keeps browser history under its legacy key and exposes corruption', async () => {
    await storage.set('sentences.v1', [{ text: 'hello' }]);
    expect(localStorage.getItem('sentra.sentences.v1')).toContain('hello');
    expect(await storage.get('sentences.v1')).toEqual([{ text: 'hello' }]);
    localStorage.setItem('sentra.sentences.v1', 'broken');
    await expect(storage.get('sentences.v1')).rejects.toThrow();
  });
});
