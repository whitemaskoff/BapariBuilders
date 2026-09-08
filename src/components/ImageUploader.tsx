import { useCallback, useEffect, useRef, useState } from 'react';
import { Upload, X, ZoomIn, ZoomOut, Check, ImageIcon, Crop } from 'lucide-react';
import * as api from '@/lib/api';

interface ImageUploaderProps {
  aspectRatio: number;
  currentUrl: string;
  folder: string;
  onUploaded: (url: string) => void;
  label?: string;
  className?: string;
  shape?: 'rect' | 'circle';
  maxWidth?: number;
}

const MAX_DISPLAY_SIZE = 1400;

function downscaleImage(img: HTMLImageElement): { canvas: HTMLCanvasElement } {
  let { naturalWidth: w, naturalHeight: h } = img;
  if (w <= MAX_DISPLAY_SIZE && h <= MAX_DISPLAY_SIZE) {
    return { canvas: null as any }; // signal: no downscale needed
  }
  const scale = Math.min(MAX_DISPLAY_SIZE / w, MAX_DISPLAY_SIZE / h);
  w = Math.round(w * scale);
  h = Math.round(h * scale);
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(img, 0, 0, w, h);
  return { canvas };
}

export function ImageUploader({
  aspectRatio,
  currentUrl,
  folder,
  onUploaded,
  label = 'Upload picture',
  className = '',
  shape = 'rect',
  maxWidth = 1600,
}: ImageUploaderProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [imgSrc, setImgSrc] = useState<string | null>(null);
  const [imgEl, setImgEl] = useState<HTMLImageElement | null>(null);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const [isDragging, setIsDragging] = useState(false);
  const dragRef = useRef<{ startX: number; startY: number; baseX: number; baseY: number } | null>(null);
  const frameRef = useRef<HTMLDivElement>(null);

  const onFileSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      setError('Please select an image file (JPG, PNG, or WebP).');
      return;
    }
    if (file.size > 15 * 1024 * 1024) {
      setError('Image must be under 15 MB.');
      return;
    }
    setError('');
    const reader = new FileReader();
    reader.onload = () => {
      const src = reader.result as string;
      const image = new Image();
      image.onload = () => {
        // Downscale very large images before showing the crop UI
        const { canvas } = downscaleImage(image);
        if (canvas) {
          const downscaledSrc = canvas.toDataURL('image/jpeg', 0.92);
          const img2 = new Image();
          img2.onload = () => {
            setImgEl(img2);
            setImgSrc(downscaledSrc);
          };
          img2.src = downscaledSrc;
        } else {
          setImgEl(image);
          setImgSrc(src);
        }
        setZoom(1);
        setOffset({ x: 0, y: 0 });
        setModalOpen(true);
      };
      image.src = src;
    };
    reader.readAsDataURL(file);
    e.target.value = '';
  };

  // Compute the scale that fits the image inside the frame at zoom=1
  const getFitScale = useCallback(() => {
    if (!imgEl || !frameRef.current) return 1;
    const fw = frameRef.current.clientWidth;
    const fh = frameRef.current.clientHeight;
    // "Cover" behavior: fill the frame completely
    return Math.max(fw / imgEl.naturalWidth, fh / imgEl.naturalHeight);
  }, [imgEl]);

  const clampOffset = useCallback((x: number, y: number, z: number) => {
    if (!imgEl || !frameRef.current) return { x, y };
    const fw = frameRef.current.clientWidth;
    const fh = frameRef.current.clientHeight;
    const fit = Math.max(fw / imgEl.naturalWidth, fh / imgEl.naturalHeight);
    const dispW = imgEl.naturalWidth * fit * z;
    const dispH = imgEl.naturalHeight * fit * z;
    let cx = x, cy = y;
    if (dispW >= fw) { cx = Math.min(0, Math.max(fw - dispW, x)); } else { cx = (fw - dispW) / 2; }
    if (dispH >= fh) { cy = Math.min(0, Math.max(fh - dispH, y)); } else { cy = (fh - dispH) / 2; }
    return { x: cx, y: cy };
  }, [imgEl]);

  // Auto-center on open and when frame size changes
  useEffect(() => {
    if (modalOpen && imgEl && frameRef.current) {
      setOffset(clampOffset(0, 0, 1));
    }
  }, [modalOpen, imgEl, clampOffset]);

  const onPointerDown = (e: React.MouseEvent | React.TouchEvent) => {
    if (!imgEl) return;
    const point = 'touches' in e ? e.touches[0] : e;
    dragRef.current = { startX: point.clientX, startY: point.clientY, baseX: offset.x, baseY: offset.y };
    setIsDragging(true);
  };

  useEffect(() => {
    if (!modalOpen) return;
    const move = (e: MouseEvent | TouchEvent) => {
      if (!dragRef.current) return;
      const point = 'touches' in e ? e.touches[0] : e;
      const dx = point.clientX - dragRef.current.startX;
      const dy = point.clientY - dragRef.current.startY;
      const clamped = clampOffset(dragRef.current.baseX + dx, dragRef.current.baseY + dy, zoom);
      setOffset(clamped);
    };
    const up = () => { dragRef.current = null; setIsDragging(false); };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    window.addEventListener('touchmove', move);
    window.addEventListener('touchend', up);
    return () => {
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
      window.removeEventListener('touchmove', move);
      window.removeEventListener('touchend', up);
    };
  }, [modalOpen, zoom, clampOffset]);

  const handleZoom = (delta: number) => {
    const newZoom = Math.max(1, Math.min(5, zoom + delta));
    setZoom(newZoom);
    setOffset((o) => clampOffset(o.x, o.y, newZoom));
  };

  const confirmCrop = async () => {
    if (!imgEl || !frameRef.current) return;
    setUploading(true);
    setError('');
    try {
      const fw = frameRef.current.clientWidth;
      const fh = frameRef.current.clientHeight;
      const fit = Math.max(fw / imgEl.naturalWidth, fh / imgEl.naturalHeight);
      const effectiveZoom = zoom * fit;
      const sourceX = -offset.x / effectiveZoom;
      const sourceY = -offset.y / effectiveZoom;
      const sourceW = fw / effectiveZoom;
      const sourceH = fh / effectiveZoom;

      const outW = Math.min(maxWidth, Math.round(fw * 2));
      const outH = Math.round(outW / aspectRatio);
      const canvas = document.createElement('canvas');
      canvas.width = outW;
      canvas.height = outH;
      const ctx = canvas.getContext('2d');
      if (!ctx) throw new Error('Could not process image');
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(imgEl, sourceX, sourceY, sourceW, sourceH, 0, 0, outW, outH);

      const blob = await new Promise<Blob>((resolve, reject) => {
        canvas.toBlob((b) => b ? resolve(b) : reject(new Error('Could not export image')), 'image/jpeg', 0.9);
      });

      const url = await api.uploadSiteImage(blob, folder);
      onUploaded(url);
      setModalOpen(false);
      setImgSrc(null);
      setImgEl(null);
    } catch {
      setError('Could not upload the image. Please try again.');
    }
    setUploading(false);
  };

  const closeModal = () => {
    setModalOpen(false);
    setImgSrc(null);
    setImgEl(null);
    setError('');
  };

  const frameStyle: React.CSSProperties = shape === 'circle'
    ? { aspectRatio: '1', borderRadius: '50%' }
    : { aspectRatio: String(aspectRatio) };

  return (
    <>
      <div className={`image-uploader-trigger ${className}`}>
        {currentUrl ? (
          <img
            src={currentUrl}
            alt="Current"
            className="uploader-preview"
            style={shape === 'circle' ? { borderRadius: '50%', objectFit: 'cover' } : undefined}
          />
        ) : (
          <div
            className="uploader-placeholder"
            style={shape === 'circle' ? { borderRadius: '50%' } : undefined}
          >
            <ImageIcon size={24} />
          </div>
        )}
        <label className="uploader-button">
          <Upload size={14} /> {label}
          <input type="file" accept="image/jpeg,image/png,image/webp" onChange={onFileSelected} style={{ display: 'none' }} />
        </label>
      </div>

      {modalOpen && imgSrc && (
        <div className="crop-modal-overlay" onMouseDown={closeModal}>
          <div className="crop-modal crop-modal-v2" onMouseDown={(e) => e.stopPropagation()}>
            <div className="crop-modal-header">
              <h3><Crop size={18} /> Adjust picture</h3>
              <button className="crop-close" onClick={closeModal}><X size={18} /></button>
            </div>
            <p className="crop-hint">Drag to reposition. Use the slider to zoom in for a tighter fit.</p>
            <div
              className={`crop-frame crop-frame-v2 ${isDragging ? 'dragging' : ''}`}
              ref={frameRef}
              style={frameStyle}
              onMouseDown={onPointerDown}
              onTouchStart={onPointerDown}
            >
              <img
                src={imgSrc}
                alt="Preview"
                className="crop-image"
                style={{
                  transform: `translate(${offset.x}px, ${offset.y}px) scale(${zoom * getFitScale()})`,
                }}
                draggable={false}
              />
              <div className="crop-frame-grid" />
            </div>
            <div className="crop-controls">
              <button className="crop-zoom-btn" onClick={() => handleZoom(-0.25)}><ZoomOut size={18} /></button>
              <input
                type="range"
                min={1}
                max={5}
                step={0.05}
                value={zoom}
                onChange={(e) => { const z = parseFloat(e.target.value); setZoom(z); setOffset((o) => clampOffset(o.x, o.y, z)); }}
                className="crop-slider"
              />
              <button className="crop-zoom-btn" onClick={() => handleZoom(0.25)}><ZoomIn size={18} /></button>
              <span className="crop-zoom-label">{Math.round(zoom * 100)}%</span>
            </div>
            {error && <div className="crop-error">{error}</div>}
            <div className="crop-actions">
              <button className="button button-outline" onClick={closeModal} disabled={uploading}>Cancel</button>
              <button className="button button-dark" onClick={confirmCrop} disabled={uploading}>
                {uploading ? 'Uploading...' : <><Check size={16} /> Save picture</>}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
