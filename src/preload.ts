import { contextBridge, ipcRenderer } from 'electron';

type BatchProgress = {
  completed: number;
  total: number;
  currentFile: string;
};

type LoadedAsset = {
  id: string;
  path: string;
  name: string;
  folder: string;
  fileSize: number;
  modifiedAt: string;
  thumbnailDataUrl: string | null;
  metadata: Record<string, unknown>;
  favorite: boolean;
  tags: string[];
  inExportQueue: boolean;
};

const api = {
  platform: process.platform,
  pickImages: () => ipcRenderer.invoke('lumina:pick-images') as Promise<string[]>,
  loadAssets: (paths: string[]) => ipcRenderer.invoke('lumina:load-assets', paths) as Promise<LoadedAsset[]>,
  pickExportFolder: () => ipcRenderer.invoke('lumina:pick-export-folder') as Promise<string | null>,
  batchExportJson: (payload: { assets: LoadedAsset[]; directory: string }) =>
    ipcRenderer.invoke('lumina:batch-export-json', payload) as Promise<{ completed: number; total: number }>,
  onBatchProgress: (listener: (event: BatchProgress) => void) => {
    const handler = (_: unknown, payload: BatchProgress) => listener(payload);
    ipcRenderer.on('lumina:batch-progress', handler);
    return () => ipcRenderer.removeListener('lumina:batch-progress', handler);
  },
};

contextBridge.exposeInMainWorld('lumina', api);
