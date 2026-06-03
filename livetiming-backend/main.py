from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Response, status, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
import asyncio
import os
from pathlib import Path
import time

STREAM_KEY = os.getenv("STREAM_KEY")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")

app = FastAPI(title="Live Score Admin API")

# Configure CORS so static web can call API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()

# Keep last broadcasted event so viewers can query current score on connect
last_event = None

# Separate manager for reload/live-edit notifications
reload_manager = ConnectionManager()

class ScoreEvent(BaseModel):
    team: str
    score: str
    delay: int = 10  # Default delay of 10 seconds if Admin doesn't provide one
    action: str = "goal"

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        # Push the latest event immediately upon connection so new viewers see it
        if last_event:
            await websocket.send_json(last_event)
            
        # Standby mode: Client only receives, doesn't send anything to server (Keep-alive)
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)


@app.websocket('/ws/reload')
async def websocket_reload(websocket: WebSocket):
    await reload_manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        reload_manager.disconnect(websocket)


async def _file_watcher_loop():
    # Watch a small set of files in the project root for modifications and notify clients
    watch_root = os.environ.get('WATCH_ROOT')
    if watch_root:
        project_root = Path(watch_root).resolve()
    else:
        project_root = Path(__file__).resolve().parent.parent
    watch_files = [project_root / 'index.html', project_root / 'admin.html']
    mtimes = {}

    for f in watch_files:
        try:
            mtimes[str(f)] = os.path.getmtime(f)
        except Exception:
            mtimes[str(f)] = None

    while True:
        for f in watch_files:
            p = str(f)
            try:
                m = os.path.getmtime(f)
            except Exception:
                m = None
            if mtimes.get(p) is None and m is not None:
                mtimes[p] = m
                # new file appeared, trigger reload and include path
                try:
                    rel = os.path.relpath(p, str(project_root)).replace('\\', '/')
                except Exception:
                    rel = os.path.basename(p)
                await reload_manager.broadcast({"type": "reload", "path": rel})
            elif m is not None and mtimes.get(p) is not None and m != mtimes.get(p):
                mtimes[p] = m
                try:
                    rel = os.path.relpath(p, str(project_root)).replace('\\', '/')
                except Exception:
                    rel = os.path.basename(p)
                await reload_manager.broadcast({"type": "reload", "path": rel})
        await asyncio.sleep(1.0)


@app.on_event("startup")
async def start_watcher():
    # start background file watcher
    asyncio.create_task(_file_watcher_loop())

@app.websocket("/ws/admin")
async def websocket_admin_endpoint(websocket: WebSocket, password: str = Query(None)):
    if not ADMIN_PASSWORD or not password or password != ADMIN_PASSWORD:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_json()
            payload = {
                "event_timestamp": time.time() * 1000,
                "team": data.get("team"),
                "score": data.get("score"),
                "delay": data.get("delay", 10),
                "action": data.get("action", "goal"),
            }
            global last_event
            last_event = payload
            await manager.broadcast(payload)
    except WebSocketDisconnect:
        pass


@app.get('/admin/last')
async def get_last_event():
    """Return the last broadcasted score event or 204 if none."""
    if last_event is None:
        return Response(status_code=204)
    return last_event

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
