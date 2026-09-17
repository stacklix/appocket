<script setup lang="ts">
import type { Action } from '../models';
defineProps<{ action: Action; data: Record<string, any> }>();
defineEmits<{ copy: [text: string] }>();
const styleLabels: Record<string, string> = {
  natural: '自然表达',
  conversational: '日常口语',
  polite: '礼貌表达',
};
</script>
<template>
  <div class="results">
    <template v-if="action === 'translate'">
      <article v-for="(item, index) in data.translations || []" :key="index" class="result-card">
        <div class="card-top">
          <span class="eyebrow">{{ index === 0 ? '01 · 直译' : '02 · 地道表达' }}</span
          ><button v-if="item.text" class="text-button" @click="$emit('copy', item.text)">
            复制
          </button>
        </div>
        <p class="translation">{{ item.text }}</p>
      </article>
      <aside v-if="data.notes?.length" class="note">
        <span class="eyebrow">表达笔记</span>
        <p v-for="(note, i) in data.notes" :key="i">{{ note }}</p>
      </aside>
    </template>
    <template v-else-if="action === 'grammar'">
      <article v-if="data.summary" class="result-card">
        <span class="eyebrow">句子结构</span>
        <p>{{ data.summary }}</p>
      </article>
      <article v-for="(item, i) in data.corrections || []" :key="i" class="result-card">
        <span class="eyebrow">语法修正</span>
        <p>
          <del>{{ item.original }}</del> → <strong>{{ item.corrected }}</strong>
        </p>
        <p>{{ item.explanation }}</p>
      </article>
      <div v-if="data.structure?.length" class="structure">
        <div v-for="(item, i) in data.structure" :key="i">
          <strong>{{ item.text }}</strong
          ><small>{{ item.part }}</small
          ><span>{{ item.role }}</span>
        </div>
      </div>
      <article v-for="(item, i) in data.grammar_points || []" :key="i" class="result-card">
        <h3>{{ item.title }}</h3>
        <p>{{ item.explanation }}</p>
        <div class="tags">
          <span v-for="(form, j) in item.inflections || []" :key="j">{{ form }}</span>
        </div>
      </article>
    </template>
    <template v-else>
      <aside v-if="data.naturalness" class="note">{{ data.naturalness }}</aside>
      <article v-for="(item, i) in data.alternatives || []" :key="i" class="result-card">
        <div class="card-top">
          <span class="eyebrow">{{ styleLabels[item.style] || item.style }}</span
          ><button v-if="item.text" class="text-button" @click="$emit('copy', item.text)">
            复制
          </button>
        </div>
        <p class="translation">{{ item.text }}</p>
        <p class="muted">{{ item.translation }}</p>
        <p>{{ item.explanation }}</p>
      </article>
    </template>
  </div>
</template>
