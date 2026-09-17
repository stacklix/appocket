export type Action = 'translate' | 'grammar' | 'improve';
export const actions: { id: Action; label: string; caption: string }[] = [
  { id: 'translate', label: '翻译', caption: '让意思准确抵达' },
  { id: 'grammar', label: '语法', caption: '读懂句子的结构' },
  { id: 'improve', label: '更地道', caption: '像母语者一样表达' },
];
export const languages = ['英语', '日语', '俄语', '希腊语'];
export interface Settings {
  protocol: 'openAi' | 'anthropic';
  baseUrl: string;
  model: string;
  token: string;
  translationLanguage: string;
  explanationLanguage: string;
  level: string;
}
export const defaults: Settings = {
  protocol: 'openAi',
  baseUrl: '',
  model: '',
  token: '',
  translationLanguage: '英语',
  explanationLanguage: '简体中文',
  level: '中级',
};
export interface Result {
  action: Action;
  data: Record<string, any>;
  model: string;
  createdAt: string;
  schemaVersion: number;
}
export interface Sentence {
  id: string;
  text: string;
  translationLanguage: string;
  explanationLanguage: string;
  level: string;
  createdAt: string;
  results: Result[];
  learningVersion: number;
}
export function endpoint(settings: Settings): string {
  let url: URL;
  try {
    url = new URL(settings.baseUrl.trim());
  } catch {
    throw new Error('请填写有效的 HTTPS API 地址');
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash)
    throw new Error('API 地址必须使用 HTTPS，不能包含账号、查询参数或片段');
  const base = url.href.replace(/\/+$/, '');
  if (settings.protocol === 'anthropic') {
    if (base.endsWith('/chat/completions')) throw new Error('接口地址与协议不匹配');
    return base.endsWith('/messages')
      ? base
      : `${base}${base.endsWith('/v1') ? '' : '/v1'}/messages`;
  }
  if (base.endsWith('/messages')) throw new Error('接口地址与协议不匹配');
  return base.endsWith('/chat/completions') ? base : `${base}/chat/completions`;
}
const languageCode = (s: string) =>
  ({
    英语: 'en',
    english: 'en',
    en: 'en',
    日语: 'ja',
    japanese: 'ja',
    ja: 'ja',
    俄语: 'ru',
    russian: 'ru',
    ru: 'ru',
    希腊语: 'el',
    greek: 'el',
    el: 'el',
  })[s.toLowerCase()] ?? s.toLowerCase();
export function validateResult(
  action: Action,
  content: string,
  text: string,
  target: string,
): Record<string, any> {
  const d = JSON.parse(
    content
      .trim()
      .replace(/^```(?:json)?\s*/, '')
      .replace(/\s*```$/, ''),
  );
  if (!d || typeof d !== 'object' || Array.isArray(d)) throw new Error('模型未返回有效对象');
  const str = (o: any, k: string) => {
    if (typeof o?.[k] !== 'string' || !o[k].trim()) throw new Error(`结果缺少 ${k}`);
  };
  const list = (o: any, k: string) => {
    if (!Array.isArray(o[k]) || o[k].some((s: unknown) => typeof s !== 'string'))
      throw new Error(`结果字段 ${k} 无效`);
  };
  const objects = (key: string, fields: string[], nonempty = false) => {
    if (!Array.isArray(d[key]) || (nonempty && !d[key].length)) throw new Error(`结果缺少 ${key}`);
    for (const item of d[key]) for (const field of fields) str(item, field);
  };
  str(d, 'source_language');
  if (action === 'translate') {
    str(d, 'translation_language');
    objects('translations', ['text', 'type'], true);
    list(d, 'notes');
    if (
      d.translations.length !== 2 ||
      d.translations[0].type !== 'direct' ||
      d.translations[1].type !== 'natural' ||
      languageCode(d.translation_language) !== languageCode(target)
    )
      throw new Error('模型未按目标语言返回直译和地道表达');
  } else {
    const prefix = action === 'grammar' ? 'analysis' : 'reference';
    if (d[`${prefix}_origin`] !== 'original' || d[`${prefix}_text`]?.trim() !== text.trim())
      throw new Error('模型更改了待分析原句，请重试');
    if (action === 'grammar') {
      if (typeof d.correct !== 'boolean') throw new Error('缺少语法判断');
      str(d, 'summary');
      objects('corrections', ['original', 'corrected', 'explanation'], !d.correct);
      if (d.correct && d.corrections.length) throw new Error('语法判断与纠错矛盾');
      objects('structure', ['text', 'part', 'role'], true);
      objects('grammar_points', ['title', 'explanation']);
      for (const point of d.grammar_points) list(point, 'inflections');
    } else {
      str(d, 'naturalness');
      objects('alternatives', ['text', 'style', 'translation', 'explanation'], true);
    }
  }
  return d;
}
