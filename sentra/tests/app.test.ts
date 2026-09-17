import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, it, expect, vi } from 'vitest';
import App from '../src/App.vue';
vi.mock('../src/api', () => ({
  analyze: vi.fn(async () => ({
    action: 'translate',
    data: {
      translations: [
        { text: 'Hello', type: 'direct' },
        { text: 'Hi', type: 'natural' },
      ],
      notes: [],
    },
    model: 'test',
    createdAt: new Date().toISOString(),
    schemaVersion: 3,
  })),
}));
beforeEach(() => {
  localStorage.clear();
  sessionStorage.clear();
  delete window.webkit;
});
it('keeps independent tab drafts, saves results and reopens/deletes history', async () => {
  localStorage.setItem(
    'sentra.preferences.v2',
    JSON.stringify({ baseUrl: 'https://provider.test/v1', model: 'test' }),
  );
  const wrapper = mount(App);
  await flushPromises();
  await wrapper.get('textarea').setValue('你好');
  await wrapper.findAll('[role=tab]')[1].trigger('click');
  expect(wrapper.get('textarea').element.value).toBe('');
  await wrapper.get('textarea').setValue('He go.');
  await wrapper.findAll('[role=tab]')[0].trigger('click');
  expect(wrapper.get('textarea').element.value).toBe('你好');
  await wrapper.get('button.primary').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('Hello');
  expect(JSON.parse(localStorage.getItem('sentra.sentences.v1')!)).toHaveLength(1);
  await wrapper.findAll('nav button')[0].trigger('click');
  expect(wrapper.findAll('.history-card')).toHaveLength(1);
  await wrapper.get('.history-open').trigger('click');
  expect(wrapper.get('textarea').element.value).toBe('你好');
  await wrapper.findAll('nav button')[0].trigger('click');
  await wrapper.get('.danger').trigger('click');
  await flushPromises();
  expect(JSON.parse(localStorage.getItem('sentra.sentences.v1')!)).toHaveLength(0);
  wrapper.unmount();
});
it('does not overwrite corrupt existing history', async () => {
  localStorage.setItem('sentra.sentences.v1', 'corrupt');
  const wrapper = mount(App);
  await flushPromises();
  expect(wrapper.text()).toContain('已停止写入');
  expect(localStorage.getItem('sentra.sentences.v1')).toBe('corrupt');
  wrapper.unmount();
});
