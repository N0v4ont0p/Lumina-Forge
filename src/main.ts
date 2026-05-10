import { app, BrowserWindow, dialog, ipcMain } from 'electron';
import path from 'node:path';
import fs from 'node:fs/promises';
import { exiftool } from 'exiftool-vendored';
import sharp from 'sharp';

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

const supportedExtensions = new Set([
  'jpg', 'jpeg', 'png', 'heic', 'heif', 'tif', 'tiff', 'gif', 'bmp', 'webp',
  'cr2', 'cr3', 'nef', 'arw', 'rw2', 'raf', 'orf', 'dng', 'pef', 'srw', 'x3f', 'mrw',
]);

let mainWindow: BrowserWindow | null = null;

const createWindow = () => {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1200,
    minHeight: 760,
    backgroundColor: '#10131dcc',
    titleBarStyle: 'hiddenInset',
    vibrancy: 'sidebar',
    visualEffectState: 'active',
    trafficLightPosition: { x: 18, y: 18 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    void mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
  } else {
    void mainWindow.loadFile(path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`));
  }
};

const isImagePath = (value: string) => supportedExtensions.has(path.extname(value).slice(1).toLowerCase());

const walkFiles = async (inputPath: string): Promise<string[]> => {
  try {
    const stat = await fs.stat(inputPath);
    if (stat.isDirectory()) {
      const entries = await fs.readdir(inputPath, { withFileTypes: true });
      const nested = await Promise.all(entries.map((entry) => walkFiles(path.join(inputPath, entry.name))));
      return nested.flat();
    }
    return isImagePath(inputPath) ? [inputPath] : [];
  } catch {
    return [];
  }
};

const buildThumbnailDataUrl = async (filePath: string): Promise<string | null> => {
  try {
    const buffer = await sharp(filePath)
      .rotate()
      .resize(640, 640, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 86 })
      .toBuffer();
    return `data:image/jpeg;base64,${buffer.toString('base64')}`;
  } catch {
    return null;
  }
};

const toAsset = async (filePath: string): Promise<LoadedAsset> => {
  const [stat, metadata, thumbnailDataUrl] = await Promise.all([
    fs.stat(filePath),
    exiftool.read(filePath).catch(() => ({} as Record<string, unknown>)),
    buildThumbnailDataUrl(filePath),
  ]);

  return {
    id: `${filePath}-${stat.mtimeMs}`,
    path: filePath,
    name: path.basename(filePath),
    folder: path.dirname(filePath),
    fileSize: stat.size,
    modifiedAt: stat.mtime.toISOString(),
    thumbnailDataUrl,
    metadata: metadata as Record<string, unknown>,
    favorite: false,
    tags: [],
    inExportQueue: false,
  };
};

ipcMain.handle('lumina:pick-images', async () => {
  if (!mainWindow) return [];
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile', 'openDirectory', 'multiSelections'],
    filters: [{ name: 'Images', extensions: Array.from(supportedExtensions) }],
  });
  return result.canceled ? [] : result.filePaths;
});

ipcMain.handle('lumina:load-assets', async (_event, inputPaths: string[]) => {
  const expanded = await Promise.all((inputPaths ?? []).map((inputPath) => walkFiles(inputPath)));
  const uniquePaths = Array.from(new Set(expanded.flat().filter((value) => isImagePath(value))));
  const assets = await Promise.all(uniquePaths.map((filePath) => toAsset(filePath)));
  return assets;
});

ipcMain.handle('lumina:pick-export-folder', async () => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory', 'createDirectory'],
  });
  return result.canceled || result.filePaths.length === 0 ? null : result.filePaths[0];
});

ipcMain.handle('lumina:batch-export-json', async (event, payload: { assets: LoadedAsset[]; directory: string }) => {
  const assets = payload.assets ?? [];
  const total = assets.length;

  for (let i = 0; i < assets.length; i += 1) {
    const asset = assets[i];
    const outputPath = path.join(payload.directory, `${path.parse(asset.name).name}.json`);
    await fs.writeFile(outputPath, JSON.stringify(asset.metadata ?? {}, null, 2), 'utf8');
    event.sender.send('lumina:batch-progress', {
      completed: i + 1,
      total,
      currentFile: asset.name,
    });
  }

  return { completed: total, total };
});

app.on('ready', createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

app.on('before-quit', () => {
  exiftool.end();
});
