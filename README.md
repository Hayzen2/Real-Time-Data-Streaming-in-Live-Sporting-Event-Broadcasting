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

### Step 3: Open the live viewing interface
The frontend is served by Nginx at:
```text
http://localhost:3000
```

The admin score update page is available at:
```text
http://localhost:3000/admin.html
```

Use `index.html` for viewing only, and `admin.html` for score updates.

If you only want to run the frontend container during development:
```bash
docker compose up -d --build frontend
```

### Step 4: Push a live stream with OBS
Open OBS Studio and configure the stream settings:
- **Service:** Custom
- **Server:** `srt://127.0.0.1:1935?streamid=YOUR_STREAM_KEY` *(replace YOUR_STREAM_KEY with your actual key from .env)*
- **Stream Key:** *(Leave this blank!)*
Then click **Start Streaming**.

You can also open `index.html` directly in your browser, but the Dockerized frontend is the recommended option.

## Deployment Guide (Cloud Server)
This platform is fully ready to be deployed to a VPS (Virtual Private Server) like AWS EC2, DigitalOcean, or Linode.

1. Clone this repository onto your cloud server.
2. Run `docker compose up -d --build` on the server.
3. **Connecting OBS:** From your local broadcasting computer, open OBS Studio. Instead of `127.0.0.1`, point the Server URL to your cloud server's Public IP Address using SRT:
   - **Server:** `srt://<YOUR_SERVER_PUBLIC_IP>:1935?streamid=YOUR_STREAM_KEY` *(replace YOUR_STREAM_KEY with the value in your .env file)*
   - **Stream Key:** *(Leave this blank!)*
4. **Viewers:** Users can watch the stream by visiting `http://<YOUR_SERVER_PUBLIC_IP>:3000`.

*Note: The frontend code (`index.html`) automatically detects the host IP, so no code changes are required to the WebSocket or HLS URLs when deploying!*

## System Problems Addressed & How We Solved Them

### 1. Reducing Video Streaming Latency
This problem comes from encoding, network transmission, and cloud processing.
- **Low-latency protocols**: Move from traditional HLS/DASH to LL-HLS (Low-Latency HLS) or WebRTC. WebRTC can reduce latency from tens of seconds to under 1 second.
- **Cloud pipeline optimization**: To reduce the processing time when the video stream from the camera is sent to the cloud, use specialized media cloud services such as AWS Elemental MediaLive to speed up transcoding and packaging in real time.

**How we solved it:** Standard HLS streaming usually introduces a 15–30 second delay. To solve this, we heavily optimized our HLS configuration. We configured the FFmpeg transcoder to generate very short, 2-second video chunks (`-hls_time 2`). On the frontend, we configured `hls.js` with aggressive Live Sync rules (`liveSyncDurationCount: 2` and `maxLiveSyncPlaybackRate: 1.5`) to force the player to continuously stay as close to the "live edge" as possible. This brings the end-to-end latency down to a highly competitive 4–6 seconds. *(For future sub-second latency, the HLS delivery pipeline could be replaced with a WebRTC SFU).*

### 2. Solving API Rate Limit and Quota Bottlenecks
Continuous API polling is unstable and can easily break data updates.
- **Backend-for-Frontend layer (BFF)**: Avoid having client devices call the sports API directly. Build an intermediate server that calls the API at allowed intervals and stores the results in a cache layer such as Redis.
- **WebSocket push architecture**: From that intermediate server, use high-performance asynchronous frameworks such as FastAPI together with WebSockets to actively push the latest score data to thousands of clients at the same time, removing pressure from the API provider.

**How we solved it:** We built a custom FastAPI backend utilizing WebSockets. Instead of having thousands of viewers constantly polling an external sports API for score updates, viewers maintain a persistent, low-resource WebSocket connection. The backend acts as the single source of truth and actively pushes goal events (`{"type": "goal"}`) out to all clients exactly when they happen. This completely eliminates API rate limiting issues.

### 3. Handling Network Instability
Poor network conditions on the viewer side can cause packet loss, jitter, and video interruption.
- **Adaptive Bitrate Streaming (ABR)**: The cloud system generates multiple video streams at different resolutions (1080p, 720p, 480p). The client-side player continuously measures the real bandwidth and smoothly switches between streams to avoid buffering.
- **Resilient transport protocol**: Use SRT (Secure Reliable Transport) for the stream uplink from the stadium to the cloud. SRT handles packet loss and jitter much better than traditional RTMP, ensuring a more stable stream even over unreliable networks.

**How we solved it:** We use SRT (Secure Reliable Transport) for the stream uplink from the stadium to the cloud. OBS broadcasts the stream via UDP to our FFmpeg SRT Listener, ensuring incredible stability on bad networks. Simultaneously, the transcoder dynamically generates three separate HLS playlists at different quality levels (1080p, 720p, and 480p). The frontend video player (`hls.js`) reads the newly generated `master.m3u8` playlist, measures the viewer's internet speed in real-time, and seamlessly switches between quality tiers to prevent buffering on poor connections.

### 4. Synchronizing Score and Video
Scores update faster than video, which can spoil the result before viewers see the event on screen.
- **Insert metadata into the video stream (SEI)**: Embed absolute timestamps into the video stream using SEI (Supplemental Enhancement Information).
- **Smart client buffer**: When the client receives a goal event over WebSocket, it should not render the score immediately. Instead, it reads the event timestamp, compares it with the SEI metadata for the currently displayed frame, and keeps the score in a queue until the video reaches the matching moment.

**How we solved it:** We achieved true wallclock time alignment. Our FFmpeg transcoder is configured to inject the exact real-world time that each video frame was encoded directly into the HLS stream chunks using the `-hls_flags program_date_time` parameter. On the frontend, `hls.js` extracts this metadata. When a score event arrives via WebSocket, the client temporarily holds it in a visual queue until the video playback time catches up to the exact millisecond the goal occurred in real life, preventing "future spoilers."

## Next Steps and Improvements
- Improve the transcoding pipeline with hardware acceleration (NVENC/VAAPI) for production-grade performance and lower CPU utilization.
- Package the frontend assets into a more robust framework (React/Vue) for easier state management of complex match data.
- Introduce LL-HLS (fMP4 + chunked transfer) to further push the HLS latency bounds down towards 2 seconds.
