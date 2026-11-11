/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => {
  const devServer = command === 'serve' && mode !== 'test'
  const backendUrl = process.env.BACKEND_URL
  if (devServer && !backendUrl) {
    throw new Error('BACKEND_URL must be set for the dev server (see compose.yaml)')
  }

  return {
    plugins: [react()],
    server: devServer ? { proxy: { '/api': backendUrl! } } : undefined,
    test: {
      environment: 'jsdom',
      setupFiles: ['./src/test/setup.ts'],
      // Load the real stylesheet (only this one) so style tests can inspect its rules.
      css: { include: [/src\/index\.css/] },
    },
  }
})
