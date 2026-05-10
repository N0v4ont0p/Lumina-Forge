export {};

declare global {
  type LuminaAsset = {
    [key: string]: unknown;
  };

  interface Window {
    lumina: {
      platform: string;
      pickImages: () => Promise<string[]>;
      loadAssets: (paths: string[]) => Promise<LuminaAsset[]>;
      pickExportFolder: () => Promise<string | null>;
      batchExportJson: (payload: { assets: LuminaAsset[]; directory: string }) => Promise<{ completed: number; total: number }>;
      onBatchProgress: (listener: (event: { completed: number; total: number; currentFile: string }) => void) => () => void;
    };
  }
}
