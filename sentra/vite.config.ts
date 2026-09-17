import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
export default defineConfig({ plugins: [vue()], base: './', build: { target: 'safari16', outDir: '../dist/sentra', emptyOutDir: true }, test: { environment: 'jsdom', setupFiles: ['./tests/setup.ts'] } });
