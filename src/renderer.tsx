import React from 'react';
import { createRoot } from 'react-dom/client';
import { AnimatePresence, motion } from 'framer-motion';
import { Grid2X2, LayoutPanelTop, Plus, Star, Tag, Upload, Folder, Sparkles } from 'lucide-react';
import { Button } from './components/ui/button';
import { ProgressRing } from './components/ui/progress-ring';
import { cn, formatBytes } from './lib/utils';
import './index.css';

type Asset = {
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

type SidebarItem =
  | { kind: 'all'; title: string }
  | { kind: 'favorites'; title: string }
  | { kind: 'tagged'; title: string }
  | { kind: 'exportQueue'; title: string }
  | { kind: 'folder'; title: string; folder: string };

const spring = { type: 'spring', stiffness: 420, damping: 34, mass: 0.65 };

function App() {
  const [assets, setAssets] = React.useState<Asset[]>([]);
  const [selected, setSelected] = React.useState<Asset | null>(null);
  const [sidebarItem, setSidebarItem] = React.useState<SidebarItem>({ kind: 'all', title: 'All Images' });
  const [isMasonry, setIsMasonry] = React.useState(true);
  const [showBatch, setShowBatch] = React.useState(false);
  const [batch, setBatch] = React.useState({ completed: 0, total: 0, currentFile: '' });

  React.useEffect(() => {
    return window.lumina.onBatchProgress((payload) => setBatch(payload));
  }, []);

  const folders = React.useMemo(() => {
    const map = new Map<string, number>();
    assets.forEach((asset) => map.set(asset.folder, (map.get(asset.folder) ?? 0) + 1));
    return Array.from(map.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [assets]);

  const filtered = React.useMemo(() => {
    switch (sidebarItem.kind) {
      case 'favorites':
        return assets.filter((asset) => asset.favorite);
      case 'tagged':
        return assets.filter((asset) => asset.tags.length > 0);
      case 'exportQueue':
        return assets.filter((asset) => asset.inExportQueue);
      case 'folder':
        return assets.filter((asset) => asset.folder === sidebarItem.folder);
      default:
        return assets;
    }
  }, [assets, sidebarItem]);

  const pickImages = async () => {
    const paths = await window.lumina.pickImages();
    if (!paths.length) return;
    const loaded = await window.lumina.loadAssets(paths);
    setAssets((prev) => {
      const map = new Map(prev.map((asset) => [asset.path, asset]));
      loaded.forEach((asset) => map.set(asset.path, asset));
      return Array.from(map.values());
    });
  };

  const toggleFavorite = (id: string) => {
    setAssets((prev) => prev.map((asset) => (asset.id === id ? { ...asset, favorite: !asset.favorite } : asset)));
  };

  const toggleExportQueue = (id: string) => {
    setAssets((prev) =>
      prev.map((asset) => (asset.id === id ? { ...asset, inExportQueue: !asset.inExportQueue } : asset)),
    );
  };

  const startBatchExport = async () => {
    const queued = assets.filter((asset) => asset.inExportQueue);
    const scope = queued.length ? queued : filtered;
    if (!scope.length) return;

    if (!queued.length) {
      setAssets((prev) => prev.map((asset) => (scope.some((q) => q.id === asset.id) ? { ...asset, inExportQueue: true } : asset)));
    }

    const directory = await window.lumina.pickExportFolder();
    if (!directory) return;

    setBatch({ completed: 0, total: scope.length, currentFile: '' });
    setShowBatch(true);
    await window.lumina.batchExportJson({ assets: scope, directory });
  };

  return (
    <div className="h-screen w-screen bg-app text-white overflow-hidden">
      <div className="h-14 px-5 flex items-center justify-between border-b border-white/10 app-drag">
        <div className="flex items-center gap-2 text-sm tracking-wide opacity-80">
          <img src="/luminaforgelogo.png" alt="Lumina Forge logo" className="h-6 w-6 rounded-md object-cover border border-white/20" />
          <span>Lumina Forge · Liquid Glass</span>
        </div>
        <div className="text-xs opacity-60">Electron + React 19 + Tailwind + Framer Motion</div>
      </div>

      <div className="h-[calc(100vh-56px)] grid grid-cols-[280px_1fr_360px] gap-3 p-3">
        <aside className="glass-panel p-4 flex flex-col gap-4 overflow-hidden">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold text-lg">Library</h2>
            <Button size="icon" onClick={pickImages}>
              <Plus className="h-4 w-4" />
            </Button>
          </div>
          <div className="space-y-1">
            {[
              { key: 'all', label: 'All Images', icon: Grid2X2 },
              { key: 'favorites', label: 'Favorites', icon: Star },
              { key: 'tagged', label: 'Tagged', icon: Tag },
              { key: 'exportQueue', label: 'Export Queue', icon: Upload },
            ].map((item) => {
              const Icon = item.icon;
              const active = sidebarItem.kind === item.key;
              return (
                <button
                  key={item.key}
                  className={cn('sidebar-item', active && 'sidebar-item-active')}
                  onClick={() => setSidebarItem({ kind: item.key as SidebarItem['kind'], title: item.label } as SidebarItem)}
                >
                  <Icon className="h-4 w-4" />
                  <span>{item.label}</span>
                </button>
              );
            })}
          </div>
          <div className="border-t border-white/10 pt-3 overflow-y-auto">
            <h3 className="text-xs uppercase tracking-widest text-white/60 mb-2">Folders</h3>
            <div className="space-y-1">
              {folders.map(([folderPath, count]) => (
                <button
                  key={folderPath}
                  className={cn('sidebar-item', sidebarItem.kind === 'folder' && sidebarItem.folder === folderPath && 'sidebar-item-active')}
                  onClick={() => setSidebarItem({ kind: 'folder', title: folderPath.split('/').pop() || folderPath, folder: folderPath })}
                >
                  <Folder className="h-4 w-4" />
                  <span className="truncate">{folderPath.split('/').pop() || folderPath}</span>
                  <span className="ml-auto text-xs text-white/60">{count}</span>
                </button>
              ))}
            </div>
          </div>
        </aside>

        <main className="glass-panel p-4 overflow-hidden">
          <div className="flex items-center justify-between mb-3">
            <div>
              <h2 className="text-lg font-semibold">{sidebarItem.title}</h2>
              <p className="text-xs text-white/60">{filtered.length} assets</p>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="ghost" onClick={() => setIsMasonry((prev) => !prev)}>
                {isMasonry ? <Grid2X2 className="h-4 w-4" /> : <LayoutPanelTop className="h-4 w-4" />} View
              </Button>
              <Button onClick={startBatchExport}>Batch Export</Button>
            </div>
          </div>

          <div className={cn('h-[calc(100%-56px)] overflow-y-auto pr-2', isMasonry ? 'columns-3 gap-3 [column-fill:_balance]' : 'grid grid-cols-4 gap-3')}>
            <AnimatePresence>
              {filtered.map((asset, index) => (
                <motion.button
                  key={asset.id}
                  layout
                  layoutId={`card-${asset.id}`}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0, transition: { ...spring, delay: Math.min(index, 18) * 0.02 } }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  whileHover={{ y: -5, scale: 1.035 }}
                  transition={spring}
                  onClick={() => setSelected(asset)}
                  className={cn('glass-card group relative mb-3 w-full text-left overflow-hidden', !isMasonry && 'h-44')}
                  style={{ breakInside: 'avoid' }}
                >
                  {asset.thumbnailDataUrl ? (
                    <motion.img
                      layoutId={`thumb-${asset.id}`}
                      src={asset.thumbnailDataUrl}
                      alt={asset.name}
                      className={cn('w-full object-cover', isMasonry ? 'h-auto min-h-[120px]' : 'h-full')}
                    />
                  ) : (
                    <div className="h-44 w-full flex items-center justify-center text-white/50">No Preview</div>
                  )}
                  <div className="absolute bottom-2 left-2 right-2 glass-label p-2">
                    <div className="text-xs font-medium truncate">{asset.name}</div>
                    <div className="text-[11px] text-white/70">{formatBytes(asset.fileSize)}</div>
                  </div>
                </motion.button>
              ))}
            </AnimatePresence>
          </div>
        </main>

        <section className="glass-panel p-4 overflow-y-auto">
          {selected ? (
            <motion.div key={selected.id} initial={{ opacity: 0, y: 18 }} animate={{ opacity: 1, y: 0 }} transition={spring}>
              <motion.div layoutId={`thumb-${selected.id}`} className="overflow-hidden rounded-2xl border border-white/10 mb-4">
                {selected.thumbnailDataUrl ? (
                  <img src={selected.thumbnailDataUrl} alt={selected.name} className="w-full h-52 object-cover" />
                ) : (
                  <div className="h-52 flex items-center justify-center text-white/50">No Preview</div>
                )}
              </motion.div>
              <div className="flex gap-2 mb-4">
                <Button variant={selected.favorite ? 'secondary' : 'ghost'} onClick={() => toggleFavorite(selected.id)}>
                  <Star className="h-4 w-4" /> {selected.favorite ? 'Favorited' : 'Favorite'}
                </Button>
                <Button variant={selected.inExportQueue ? 'secondary' : 'ghost'} onClick={() => toggleExportQueue(selected.id)}>
                  <Upload className="h-4 w-4" /> {selected.inExportQueue ? 'Queued' : 'Queue'}
                </Button>
              </div>
              <h3 className="font-semibold mb-2">Metadata</h3>
              <div className="space-y-2 text-sm">
                {Object.entries(selected.metadata)
                  .slice(0, 20)
                  .map(([key, value]) => (
                    <div key={key} className="grid grid-cols-[120px_1fr] gap-3 py-1 border-b border-white/5">
                      <span className="text-white/60 truncate">{key}</span>
                      <span className="truncate">{String(value)}</span>
                    </div>
                  ))}
              </div>
            </motion.div>
          ) : (
            <div className="h-full flex flex-col items-center justify-center text-center text-white/60">
              <Sparkles className="h-10 w-10 mb-3" />
              <p className="font-medium">Select an image</p>
              <p className="text-sm">Matched-geometry transitions and metadata details appear here.</p>
            </div>
          )}
        </section>
      </div>

      {showBatch && (
        <div className="fixed inset-0 bg-black/45 backdrop-blur-sm flex items-center justify-center z-50">
          <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="glass-panel w-[380px] p-6">
            <h3 className="text-lg font-semibold mb-1">Batch Export</h3>
            <p className="text-sm text-white/70 mb-5">{batch.currentFile || 'Preparing export…'}</p>
            <ProgressRing completed={batch.completed} total={batch.total} />
            <div className="mt-6 flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setShowBatch(false)}>Close</Button>
            </div>
          </motion.div>
        </div>
      )}
    </div>
  );
}

const rootEl = document.getElementById('root');
if (!rootEl) {
  throw new Error('Failed to find root DOM element with id "root". Ensure index.html contains <div id="root"></div>.');
}
createRoot(rootEl).render(<App />);
