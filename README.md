# Live Sports Streaming Platform Demo

## Installation and Run Guide

### Step 1: Start the full system with Docker
Make sure Docker and Docker Compose are installed. Run the following command from the project root:
```bash
docker compose up -d --build
```
If port 1935 is already in use by another application, stop that application or change the port in docker-compose.yml.

### Step 2: Access the backend
After Docker Compose finishes starting, the FastAPI backend will be available at:
```text
http://localhost:8000
```

If you only want to run the backend container during development:
```bash
docker compose up -d --build backend
```

### Step 3: Push a live stream with OBS
Open OBS Studio and configure the stream settings:
- **Service:** Custom
- **Server:** `rtmp://127.0.0.1/live`
- **Stream Key:** `test`
Then click **Start Streaming**.

### Step 4: Open the live viewing interface
- Open `index.html` directly in your browser.
- Or, for a better local setup, run a static server:
```bash
python3 -m http.server 3000
```
Then open `http://localhost:3000` in your browser.

## System Problems Addressed

### 1. Reducing Video Streaming Latency
This problem comes from encoding, network transmission, and cloud processing.
- **Low-latency protocols**: Move from traditional HLS/DASH to LL-HLS (Low-Latency HLS) or WebRTC. WebRTC can reduce latency from tens of seconds to under 1 second.
- **Cloud pipeline optimization**: To reduce the processing time when the video stream from the camera is sent to the cloud, use specialized media cloud services such as AWS Elemental MediaLive to speed up transcoding and packaging in real time.

### 2. Solving API Rate Limit and Quota Bottlenecks
Continuous API polling is unstable and can easily break data updates.
- **Backend-for-Frontend layer (BFF)**: Avoid having client devices call the sports API directly. Build an intermediate server that calls the API at allowed intervals and stores the results in a cache layer such as Redis.
- **WebSocket push architecture**: From that intermediate server, use high-performance asynchronous frameworks such as FastAPI together with WebSockets to actively push the latest score data to thousands of clients at the same time, removing pressure from the API provider.

### 3. Handling Network Instability
Poor network conditions on the viewer side can cause packet loss, jitter, and video interruption.
- **Adaptive Bitrate Streaming (ABR)**: The cloud system generates multiple video streams at different resolutions (1080p, 720p, 480p). The client-side player continuously measures the real bandwidth and smoothly switches between streams to avoid buffering.
- **Resilient transport protocol**: Instead of RTMP, use SRT (Secure Reliable Transport) for the stream uplink from the stadium to the cloud. SRT handles packet loss and jitter much better.

### 4. Synchronizing Score and Video
Scores update faster than video, which can spoil the result before viewers see the event on screen.
- **Insert metadata into the video stream (SEI)**: Embed absolute timestamps into the video stream using SEI (Supplemental Enhancement Information).
- **Smart client buffer**: When the client receives a goal event over WebSocket, it should not render the score immediately. Instead, it reads the event timestamp, compares it with the SEI metadata for the currently displayed frame, and keeps the score in a queue until the video reaches the matching moment.
