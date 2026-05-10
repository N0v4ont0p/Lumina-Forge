import { defineConfig } from 'vite';

// https://vitejs.dev/config
// Native modules (sharp, exiftool-vendored) must NOT be bundled by Vite/Rollup;
// they need to be required at runtime so their platform-specific binaries
// (e.g. @img/sharp-darwin-arm64) resolve correctly inside the packaged app.
export default defineConfig({
  build: {
    rollupOptions: {
      external: ['sharp', 'exiftool-vendored'],
    },
    commonjsOptions: {
      // Help rollup-plugin-commonjs resolve sharp's dynamic require of its
      // platform binary loader on macOS arm64.
      dynamicRequireTargets: [
        'node_modules/sharp/lib/sharp.js',
        'node_modules/@img/sharp-darwin-arm64/**/*',
        'node_modules/@img/sharp-libvips-darwin-arm64/**/*',
      ],
    },
  },
});
