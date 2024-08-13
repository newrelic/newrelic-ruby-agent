/// <reference types="vitest" />
import { defineConfig } from 'vite';

// https://vitejs.dev/config/
export default defineConfig({
  test: {
    setupFiles: './src/setup.ts',
    clearMocks: true,
    mockReset: true,
    restoreMocks: true,
    coverage: {
      reporter: ['html', 'lcov', 'text'],
    },
    deps: {
      inline: [/github-action-test-helper/]
    },
  },
});
