import type { ForgeConfig } from '@electron-forge/shared-types';
import { MakerZIP } from '@electron-forge/maker-zip';
import { AutoUnpackNativesPlugin } from '@electron-forge/plugin-auto-unpack-natives';
import { VitePlugin } from '@electron-forge/plugin-vite';

const config: ForgeConfig = {
  packagerConfig: {
    icon: './logo.icns',
    extraResource: ['./logo.icns'],
    // Required by AutoUnpackNativesPlugin – the app must be packaged as an
    // asar archive so the plugin can unpack native binaries from it.
    asar: true,
    // Extract native modules from the asar archive so that .node binaries
    // (sharp, exiftool-vendored's exiftool binary, and batch-cluster) can
    // be loaded at runtime on macOS arm64.  Belt-and-suspenders alongside
    // AutoUnpackNativesPlugin below.
    asarUnpack: [
      '**/node_modules/exiftool-vendored/**',
      '**/node_modules/batch-cluster/**',
      '**/node_modules/sharp/**',
      '**/node_modules/@img/**',
    ],
    appBundleId: 'com.luminaforge.app',
    appCategoryType: 'public.app-category.photography',
    osxSign: false,
    // Override the default ignore filter from @electron-forge/plugin-vite,
    // which strips everything except `.vite/`. We allow the entire
    // node_modules tree through so that runtime deps of whitelisted native
    // modules (e.g. luxon, which is required by exiftool-vendored) are never
    // accidentally stripped. Vite already bundles all renderer/preload code
    // into .vite/, so passing node_modules through does not bloat bundles.
    ignore: (file: string) => {
      if (!file) return false;
      if (file.startsWith('/.vite')) return false;
      if (file === '/package.json') return false;
      if (file.startsWith('/node_modules')) return false;
      return true;
    },
  },
  rebuildConfig: {},
  makers: [new MakerZIP({}, ['darwin'])],
  plugins: [
    // Unpack native node modules (e.g. sharp + @img/sharp-darwin-arm64
    // and @img/sharp-libvips-darwin-arm64) from the asar archive so that
    // their .node binaries can be loaded at runtime in the packaged app.
    new AutoUnpackNativesPlugin({}),
    new VitePlugin({
      build: [
        {
          entry: 'src/main.ts',
          config: 'vite.main.config.ts',
          target: 'main',
        },
        {
          entry: 'src/preload.ts',
          config: 'vite.preload.config.ts',
          target: 'preload',
        },
      ],
      renderer: [
        {
          name: 'main_window',
          config: 'vite.renderer.config.ts',
        },
      ],
    }),
  ],
};

export default config;
