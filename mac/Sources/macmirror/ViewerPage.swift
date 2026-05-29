import Foundation

/// The viewer page served to the Tesla browser, embedded so the app needs no
/// external resource bundle (keeps the .app trivial to package).
let viewerHTML = #"""
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>mactesla — 확장 디스플레이</title>
<style>
  :root { color-scheme: dark; }
  html, body {
    margin: 0; padding: 0; height: 100%; width: 100%;
    background: #000; overflow: hidden;
    font-family: -apple-system, system-ui, sans-serif;
    -webkit-user-select: none; user-select: none;
  }
  #screen {
    position: absolute; inset: 0;
    width: 100%; height: 100%;
    object-fit: contain;
    background: #000;
    display: block;
  }
  #overlay {
    position: absolute; inset: 0;
    display: flex; align-items: center; justify-content: center;
    flex-direction: column; gap: 16px;
    color: #ddd; text-align: center;
    background: radial-gradient(circle at center, #111 0%, #000 80%);
    transition: opacity .4s ease;
    pointer-events: none;
  }
  #overlay.hidden { opacity: 0; }
  #overlay h1 { font-size: 28px; font-weight: 600; margin: 0; letter-spacing: -0.5px; }
  #overlay p  { font-size: 16px; margin: 0; color: #888; }
  .spinner {
    width: 42px; height: 42px; border-radius: 50%;
    border: 4px solid #333; border-top-color: #4a9eff;
    animation: spin 1s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  #hud {
    position: absolute; top: 8px; right: 12px;
    font-size: 12px; color: #4a9eff; opacity: 0;
    font-variant-numeric: tabular-nums;
    transition: opacity .3s; pointer-events: none;
    text-shadow: 0 1px 2px #000;
  }
  body.show-hud #hud { opacity: 0.85; }
</style>
</head>
<body>
  <canvas id="screen"></canvas>
  <div id="hud">--</div>
  <div id="overlay">
    <div class="spinner"></div>
    <h1>맥북에 연결 중…</h1>
    <p id="sub">mactesla</p>
  </div>

<script>
(() => {
  const canvas  = document.getElementById('screen');
  const ctx     = canvas.getContext('2d', { alpha: false, desynchronized: true });
  const overlay = document.getElementById('overlay');
  const sub     = document.getElementById('sub');
  const hud     = document.getElementById('hud');

  // WebSocket shares the same origin/port as the page (so a single tunnel
  // hostname covers both). Uses wss automatically when served over https.
  const wsProto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsURL   = `${wsProto}//${location.host}/ws`;

  let ws = null;
  let reconnectDelay = 500;       // ms, backs off to 4s
  let frames = 0, bytes = 0, lastTick = performance.now();
  let decoding = false;           // drop frames if we fall behind

  function setOverlay(visible, title, subtitle) {
    overlay.classList.toggle('hidden', !visible);
    if (title) overlay.querySelector('h1').textContent = title;
    if (subtitle !== undefined) sub.textContent = subtitle;
  }

  function fitCanvas(w, h) {
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
  }

  async function onFrame(buf) {
    // Backpressure: if a decode is already running, skip this frame.
    if (decoding) { bytes += buf.byteLength; return; }
    decoding = true;
    try {
      const bitmap = await createImageBitmap(new Blob([buf], { type: 'image/jpeg' }));
      fitCanvas(bitmap.width, bitmap.height);
      ctx.drawImage(bitmap, 0, 0);
      bitmap.close();
      frames++; bytes += buf.byteLength;
      if (!overlay.classList.contains('hidden')) setOverlay(false);
    } catch (e) {
      /* malformed frame; ignore */
    } finally {
      decoding = false;
    }
  }

  function connect() {
    setOverlay(true, '맥북에 연결 중…', wsURL);
    try { ws = new WebSocket(wsURL); }
    catch (e) { scheduleReconnect(); return; }
    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      reconnectDelay = 500;
      setOverlay(true, '스트림 대기 중…', '');
    };
    ws.onmessage = (ev) => {
      if (typeof ev.data === 'string') return;   // reserved for control msgs
      onFrame(ev.data);
    };
    ws.onclose = () => { setOverlay(true, '연결 끊김 — 재시도 중…', wsURL); scheduleReconnect(); };
    ws.onerror = () => { try { ws.close(); } catch (_) {} };
  }

  function scheduleReconnect() {
    ws = null;
    setTimeout(connect, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 1.6, 4000);
  }

  // FPS / bitrate HUD, tap to toggle.
  setInterval(() => {
    const now = performance.now();
    const dt = (now - lastTick) / 1000;
    const fps = frames / dt;
    const mbps = (bytes * 8 / 1e6) / dt;
    hud.textContent = `${fps.toFixed(0)} fps · ${mbps.toFixed(1)} Mbps`;
    frames = 0; bytes = 0; lastTick = now;
  }, 1000);

  document.body.addEventListener('click', () => {
    document.body.classList.toggle('show-hud');
  });

  // Keep the Tesla screen awake if the API is present.
  if ('wakeLock' in navigator) {
    const lock = () => navigator.wakeLock.request('screen').catch(() => {});
    lock();
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') lock();
    });
  }

  connect();
})();
</script>
</body>
</html>
"""#
