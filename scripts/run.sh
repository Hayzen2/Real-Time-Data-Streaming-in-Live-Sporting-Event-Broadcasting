#!/bin/sh
set -e

# Simple ffmpeg-based transcoder that reads an RTMP source and writes multi-bitrate HLS
# The container expects env vars: INPUT_URL and OUTPUT_DIR (defaults set in compose)

INPUT_URL=${INPUT_URL:-rtmp://rtmp-server/live/test}
OUTPUT_DIR=${OUTPUT_DIR:-/var/www/hls}

mkdir -p "$OUTPUT_DIR"

# Remove previous output to avoid stale files
rm -rf "$OUTPUT_DIR"/*

# Variant directories
OUT1080="$OUTPUT_DIR/1080p"
OUT720="$OUTPUT_DIR/720p"
OUT480="$OUTPUT_DIR/480p"

mkdir -p "$OUT1080" "$OUT720" "$OUT480"

# Start three ffmpeg processes (one per rendition). Simple and robust for a prototype.
echo "Starting 1080p ffmpeg..."
(
ffmpeg -hide_banner -y -i "$INPUT_URL" \
  -c:v libx264 -b:v 3500k -s 1920x1080 -preset veryfast -g 48 -keyint_min 48 -bf 2 -maxrate 3850k -bufsize 7000k -profile:v high -x264-params "nal-hrd=cbr" \
  -c:a aac -b:a 128k \
  -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+program_date_time \
  -hls_segment_filename "$OUT1080/seg_%03d.ts" "$OUT1080/stream.m3u8"
) &
pid1=$!

echo "Starting 720p ffmpeg..."
(
ffmpeg -hide_banner -y -i "$INPUT_URL" \
  -c:v libx264 -b:v 1800k -s 1280x720 -preset veryfast -g 48 -keyint_min 48 -bf 2 -maxrate 2100k -bufsize 4200k -profile:v main -x264-params "nal-hrd=cbr" \
  -c:a aac -b:a 128k \
  -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+program_date_time \
  -hls_segment_filename "$OUT720/seg_%03d.ts" "$OUT720/stream.m3u8"
) &
pid2=$!

echo "Starting 480p ffmpeg..."
(
ffmpeg -hide_banner -y -i "$INPUT_URL" \
  -c:v libx264 -b:v 800k -s 854x480 -preset veryfast -g 48 -keyint_min 48 -bf 2 -maxrate 920k -bufsize 1600k -profile:v baseline -x264-params "nal-hrd=cbr" \
  -c:a aac -b:a 128k \
  -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+program_date_time \
  -hls_segment_filename "$OUT480/seg_%03d.ts" "$OUT480/stream.m3u8"
) &
pid3=$!

# Create master playlist (references variant playlists)
cat > "$OUTPUT_DIR/master.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:3
# 1080p
#EXT-X-STREAM-INF:BANDWIDTH=3850000,RESOLUTION=1920x1080
1080p/stream.m3u8
# 720p
#EXT-X-STREAM-INF:BANDWIDTH=2100000,RESOLUTION=1280x720
720p/stream.m3u8
# 480p
#EXT-X-STREAM-INF:BANDWIDTH=920000,RESOLUTION=854x480
480p/stream.m3u8
EOF

echo "Transcoder started; pids: $pid1 $pid2 $pid3"

# Wait for ffmpeg processes
wait $pid1 $pid2 $pid3
