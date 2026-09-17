<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue';
import { authorizeOrigin, copyText, createID, isNative, ready, storage } from '@appocket/host-sdk';
import {
  actions,
  defaults,
  endpoint,
  languages,
  type Action,
  type Result,
  type Sentence,
  type Settings,
} from './models';
import { analyze } from './api';
import { partialResult } from './partial';
import ResultView from './components/ResultView.vue';
const settings = reactive<Settings>({ ...defaults });
const draftSettings = reactive<Settings>({ ...defaults });
const active = ref<Action>('translate');
const panel = ref<'learn' | 'history' | 'settings'>('learn');
const history = ref<Sentence[]>([]);
const search = ref('');
const notice = ref('');
const loaded = ref(false);
const historyWritable = ref(true);
const saving = ref(false);
const deleting = reactive(new Set<string>());
const tabs = reactive(
  Object.fromEntries(
    actions.map((a) => [
      a.id,
      {
        text: '',
        result: null as Result | null,
        progress: '',
        busy: false,
        error: '',
        controller: null as AbortController | null,
      },
    ]),
  ) as Record<
    Action,
    {
      text: string;
      result: Result | null;
      progress: string;
      busy: boolean;
      error: string;
      controller: AbortController | null;
    }
  >,
);
const tab = computed(() => tabs[active.value]);
const preview = computed(() =>
  tab.value.busy ? partialResult(tab.value.progress) : tab.value.result?.data,
);
const filtered = computed(() =>
  history.value.filter((s) =>
    `${s.text} ${JSON.stringify(s.results)}`.toLowerCase().includes(search.value.toLowerCase()),
  ),
);
let writeQueue = Promise.resolve();
function persistHistory() {
  const snapshot = JSON.parse(JSON.stringify(history.value));
  const next = writeQueue.catch(() => {}).then(() => storage.set('sentences.v1', snapshot));
  writeQueue = next;
  return next;
}
onMounted(async () => {
  try {
    const prefs = await storage.get<Partial<Settings>>('preferences.v2');
    Object.assign(settings, prefs ?? {});
    settings.token = isNative() ? '' : (sessionStorage.getItem('sentra.token') ?? '');
    if (!isNative() && !prefs) {
      const old = sessionStorage.getItem('sentra.settings.v1');
      if (old) Object.assign(settings, JSON.parse(old));
    }
    if (!languages.includes(settings.translationLanguage)) settings.translationLanguage = '英语';
  } catch {
    notice.value = '连接设置读取失败，请重新配置。';
  }
  try {
    const saved = await storage.get<Sentence[]>('sentences.v1');
    if (
      saved &&
      (!Array.isArray(saved) ||
        saved.some((s) => typeof s.text !== 'string' || !Array.isArray(s.results)))
    )
      throw new Error();
    history.value = saved ?? [];
  } catch {
    historyWritable.value = false;
    notice.value = '学习记录读取失败，已停止写入以保护原数据。请重新打开。';
  }
  loaded.value = true;
  try {
    await ready();
  } catch {
    notice.value = '宿主初始化失败，请返回后重试。';
  }
});
function openSettings() {
  Object.assign(draftSettings, settings);
  panel.value = 'settings';
}
async function saveSettings() {
  saving.value = true;
  notice.value = '';
  try {
    const url = endpoint(draftSettings);
    if (!draftSettings.model.trim()) throw new Error('请填写模型名称');
    await authorizeOrigin(new URL(url).origin);
    const { token, ...prefs } = draftSettings;
    await storage.set('preferences.v2', prefs);
    if (!isNative()) sessionStorage.setItem('sentra.token', token);
    Object.assign(settings, draftSettings);
    panel.value = 'learn';
    notice.value = '连接设置已保存，API Key 仅保留在本次页面会话。';
  } catch (e) {
    notice.value = message(e);
  } finally {
    saving.value = false;
  }
}
function clearToken() {
  draftSettings.token = '';
  settings.token = '';
  if (!isNative()) sessionStorage.removeItem('sentra.token');
}
function message(e: unknown) {
  return e instanceof Error ? e.message : String(e);
}
async function copy(text: string) {
  try {
    await copyText(text);
    notice.value = '已复制';
  } catch {
    notice.value = '复制失败，请长按文字复制';
  }
}
async function run() {
  const action = active.value,
    current = tabs[action],
    text = current.text.trim();
  if (!text || current.busy || !loaded.value || !historyWritable.value) return;
  if (text.length > 4000) {
    current.error = '每次最多输入 4000 个字符';
    return;
  }
  if (!settings.baseUrl || !settings.model) {
    openSettings();
    notice.value = '先连接你的模型服务，即可开始学习。';
    return;
  }
  const config = { ...settings };
  current.busy = true;
  current.error = '';
  current.progress = '';
  current.result = null;
  const controller = new AbortController();
  current.controller = controller;
  try {
    const result = await analyze(action, text, config, controller.signal, (value) => {
      current.progress = value;
    });
    if (controller.signal.aborted) return;
    current.result = result;
    history.value.unshift({
      id: createID(),
      text,
      translationLanguage: config.translationLanguage,
      explanationLanguage: config.explanationLanguage,
      level: config.level,
      createdAt: result.createdAt,
      results: [result],
      learningVersion: 3,
    });
    try {
      await persistHistory();
    } catch {
      notice.value = '结果已生成，但保存失败。请释放空间后点击重试保存。';
    }
  } catch (e) {
    current.error = controller.signal.aborted ? '已停止生成，未完成结果不会保存。' : message(e);
  } finally {
    current.busy = false;
    current.controller = null;
  }
}
async function retrySave() {
  try {
    await persistHistory();
    notice.value = '学习记录已保存';
  } catch {
    notice.value = '保存失败，请检查可用空间';
  }
}
function openSentence(s: Sentence) {
  const result = s.results.find((r) => r.action === active.value) ?? s.results[0];
  if (!result) return;
  const t = tabs[result.action];
  if (t.busy) {
    notice.value = '请先停止该页面的生成，再打开记录';
    return;
  }
  active.value = result.action;
  t.text = s.text;
  t.result = result;
  t.error = '';
  panel.value = 'learn';
}
async function removeSentence(s: Sentence) {
  if (!historyWritable.value || deleting.has(s.id)) return;
  deleting.add(s.id);
  history.value = history.value.filter((x) => x.id !== s.id);
  try {
    await persistHistory();
  } catch {
    if (!history.value.some((x) => x.id === s.id)) history.value.push(s);
    history.value.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    notice.value = '删除保存失败，请重试';
  } finally {
    deleting.delete(s.id);
  }
}
</script>
<template>
  <div class="shell">
    <header class="header">
      <button class="brand" @click="panel = 'learn'">
        <span class="brand-icon">S<span>·</span></span
        ><span>Sentra<small>一句，一点进步</small></span>
      </button>
      <nav aria-label="主导航">
        <button :class="{ selected: panel === 'history' }" @click="panel = 'history'">
          学习记录 <span class="count">{{ history.length }}</span></button
        ><button :class="{ selected: panel === 'settings' }" @click="openSettings">连接设置</button>
      </nav>
    </header>
    <div v-if="notice" class="notice" role="status">
      {{ notice }}
      <button v-if="notice.includes('保存失败')" class="text-button" @click="retrySave">
        重试保存</button
      ><button aria-label="关闭提示" @click="notice = ''">×</button>
    </div>
    <main v-if="panel === 'learn'" class="workspace">
      <section class="input-column">
        <div class="section-label">YOUR DAILY LANGUAGE SPACE</div>
        <div class="tabs" role="tablist" aria-label="学习模式">
          <button
            v-for="a in actions"
            :key="a.id"
            role="tab"
            :aria-selected="active === a.id"
            :class="{ active: active === a.id }"
            @click="active = a.id"
          >
            {{ a.label }}
          </button>
        </div>
        <div class="editor">
          <div class="card-top">
            <label for="sentence">你的句子</label
            ><button class="text-button" :disabled="!tab.text" @click="copy(tab.text)">复制</button>
          </div>
          <textarea
            id="sentence"
            v-model="tab.text"
            :disabled="tab.busy"
            maxlength="4000"
            placeholder="输入想理解或表达的一句话…"
            @input="tab.result = null"
          />
          <div class="editor-footer">
            <span>{{ tab.text.length }} / 4000</span
            ><button
              class="text-button"
              :disabled="tab.busy"
              @click="
                tab.text = '';
                tab.result = null;
                tab.error = '';
              "
            >
              清空
            </button>
          </div>
        </div>
        <div class="controls">
          <label v-if="active === 'translate'"
            >翻译为
            <select v-model="settings.translationLanguage" :disabled="tab.busy">
              <option v-for="l in languages" :key="l">{{ l }}</option>
            </select></label
          ><span v-else class="muted">直接分析原句，保留原文语言</span
          ><button v-if="tab.busy" class="primary stop" @click="tab.controller?.abort()">
            停止生成</button
          ><button
            v-else
            class="primary"
            :disabled="!tab.text.trim() || !loaded || !historyWritable"
            @click="run"
          >
            {{ tab.result ? '重新生成' : '开始学习' }} <span>↗</span>
          </button>
        </div>
        <div class="quiet-note">
          <span class="dot"></span
          >{{ isNative() ? '学习记录保存在这台设备' : '学习记录保存在当前浏览器' }}
          <p>每天一句，让语言慢慢成为你的习惯。</p>
        </div>
      </section>
      <section class="output-column" aria-label="学习结果" aria-live="polite">
        <div class="card-top output-heading">
          <span class="section-label">学习笔记</span
          ><span v-if="tab.busy" class="generating"
            >● {{ tab.progress ? '正在生成' : '正在连接' }}</span
          ><button
            v-else-if="tab.result"
            class="text-button"
            @click="copy(JSON.stringify(tab.result.data, null, 2))"
          >
            复制完整结果
          </button>
        </div>
        <div v-if="tab.error" class="error" role="alert">{{ tab.error }}</div>
        <ResultView
          v-if="preview && Object.keys(preview).length"
          :action="active"
          :data="preview"
          @copy="copy"
        />
        <div v-else class="empty">
          <div class="empty-art">Aa<span>あ</span></div>
          <h2>{{ tab.busy ? '正在琢磨这句话…' : '好表达，从一句话开始' }}</h2>
          <p>
            {{
              tab.busy ? '结果会逐步出现在这里。' : '写下一个句子，探索它的意思、结构和更多可能。'
            }}
          </p>
          <div class="empty-line"></div>
        </div>
      </section>
    </main>
    <main v-else-if="panel === 'history'" class="page">
      <div class="page-heading">
        <div>
          <span class="section-label">YOUR COLLECTION</span>
          <h1>学过的每一句，都在这里。</h1>
        </div>
        <button class="text-button" @click="panel = 'learn'">继续学习 ↗</button>
      </div>
      <input
        v-model="search"
        class="search"
        aria-label="搜索学习记录"
        placeholder="搜索句子或学习笔记…"
      />
      <div v-if="!filtered.length" class="empty">
        <h2>{{ search ? '没有找到相关记录' : '你的第一句，值得留下' }}</h2>
        <p>完成一次学习，结果会自动保存在这里。</p>
      </div>
      <article v-for="s in filtered" :key="s.id" class="history-card">
        <button class="history-open" @click="openSentence(s)">
          <span class="eyebrow"
            >{{ actions.find((a) => a.id === s.results[0]?.action)?.label }} ·
            {{ new Date(s.createdAt).toLocaleDateString() }}</span
          >
          <p>{{ s.text }}</p></button
        ><button class="text-button danger" aria-label="删除记录" @click="removeSentence(s)">
          删除
        </button>
      </article>
    </main>
    <main v-else class="page settings">
      <span class="section-label">MAKE IT YOURS</span>
      <h1>连接与学习偏好</h1>
      <p class="muted">连接你选择的模型服务。无需注册 Lingrove 账号。</p>
      <form @submit.prevent="saveSettings">
        <fieldset>
          <legend>模型连接</legend>
          <label
            >接口协议<select v-model="draftSettings.protocol">
              <option value="openAi">OpenAI 兼容</option>
              <option value="anthropic">Anthropic 兼容</option>
            </select></label
          ><label
            >API Base URL<input
              v-model="draftSettings.baseUrl"
              type="url"
              placeholder="https://api.openai.com/v1"
              required /></label
          ><label
            >模型名称<input
              v-model="draftSettings.model"
              placeholder="服务商提供的模型名称"
              required /></label
          ><label
            >API Key（服务商需要时填写）<input
              v-model="draftSettings.token"
              type="password"
              autocomplete="off"
              placeholder="仅保留在本次页面会话" /></label
          ><button type="button" class="text-button" @click="clearToken">移除 API Key</button>
        </fieldset>
        <fieldset>
          <legend>学习偏好</legend>
          <label
            >解释语言<select v-model="draftSettings.explanationLanguage">
              <option>简体中文</option>
              <option>英语</option>
              <option>日语</option>
            </select></label
          ><label
            >学习水平<select v-model="draftSettings.level">
              <option>初级</option>
              <option>中级</option>
              <option>高级</option>
            </select></label
          ><label
            >默认翻译语言<select v-model="draftSettings.translationLanguage">
              <option v-for="l in languages" :key="l">{{ l }}</option>
            </select></label
          >
        </fieldset>
        <p class="muted small">
          提交的句子将发送到你配置的服务商。浏览器预览需要服务商支持跨域请求。
        </p>
        <div class="form-actions">
          <button type="button" class="text-button" @click="panel = 'learn'">返回</button
          ><button class="primary" :disabled="saving">
            {{ saving ? '正在保存…' : '保存设置' }}
          </button>
        </div>
      </form>
    </main>
    <footer>SENTRA <span>把世界，读成自己的语言。</span></footer>
  </div>
</template>
