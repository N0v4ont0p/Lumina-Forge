import { defineConfig } from 'vite';

// https://vitejs.dev/config
// Native modules (sharp, exiftool-vendored) must NOT be bundled by Vite/Rollup;
// they need to be required at runtime so their platform-specific binaries
// (e.g. @img/sharp-darwin-arm64) resolve correctly inside the packaged app.
export default defineConfig({
  build: {
    rollupOptions: {
      external: ['sharp', 'exiftool-vendored', 'luxon'],
    },
  },
});
