#!/bin/sh

# FFmpeg-based transcoder that listens for an SRT connection and writes perfectly aligned multi-bitrate HLS.
INPUT_URL=${INPUT_URL:-"srt://0.0.0.0:1935?mode=listener"}
OUTPUT_DIR=${OUTPUT_DIR:-/var/www/hls}

echo "Initializing SRT Transcoder Pipeline..."
mkdir -p "$OUTPUT_DIR/1080p" "$OUTPUT_DIR/720p" "$OUTPUT_DIR/480p"

while true; do
    echo "Waiting for OBS to connect via SRT on UDP Port 1935..."
    
    # Clean up old segments before a new stream starts
    rm -f "$OUTPUT_DIR/master.m3u8"
    rm -f "$OUTPUT_DIR"/*/*.ts "$OUTPUT_DIR"/*/*.m3u8

    # Single FFmpeg process decodes once and outputs perfectly aligned ABR streams
    ffmpeg -hide_banner -y -i "$INPUT_URL" \
      -filter_complex "[0:v]split=3[v1][v2][v3]; [v1]scale=1920:1080[v1out]; [v2]scale=1280:720[v2out]; [v3]scale=854:480[v3out]" \
      -map "[v1out]" -c:v:0 libx264 -b:v:0 3500k -maxrate:v:0 3850k -bufsize:v:0 7000k -preset veryfast -g 48 -keyint_min 48 -profile:v high -x264-params "nal-hrd=cbr" \
      -map "[v2out]" -c:v:1 libx264 -b:v:1 1800k -maxrate:v:1 2100k -bufsize:v:1 4200k -preset veryfast -g 48 -keyint_min 48 -profile:v main -x264-params "nal-hrd=cbr" \
      -map "[v3out]" -c:v:2 libx264 -b:v:2 800k -maxrate:v:2 920k -bufsize:v:2 1600k -preset veryfast -g 48 -keyint_min 48 -profile:v baseline -x264-params "nal-hrd=cbr" \
      -map a:0 -c:a:0 aac -b:a:0 128k \
      -map a:0 -c:a:1 aac -b:a:1 128k \
      -map a:0 -c:a:2 aac -b:a:2 128k \
      -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+program_date_time \
      -var_stream_map "v:0,a:0,name:1080p v:1,a:1,name:720p v:2,a:2,name:480p" \
      -master_pl_name master.m3u8 \
      -hls_segment_filename "$OUTPUT_DIR/%v/seg_%03d.ts" \
      "$OUTPUT_DIR/%v/stream.m3u8"
      
    echo "Stream disconnected. Restarting SRT listener in 2 seconds..."
    sleep 2
done
