set -e

# --- Налаштування (змініть при потребі) ---
WIFI_SSID="YOUR_SSID"
WIFI_PASS="YOUR_WIFI_PASS"
RTSP_USER="user"
RTSP_PASS="pass"
CAM_RES="1280x720"
CAM_FPS="30"
CAM_BITRATE="2000k"
WORKDIR="$HOME/orangepi-mediamtx"
# -----------------------------------------

# 1) Wi‑Fi конфіг (без редактора)
sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=UA

network={
  ssid="$WIFI_SSID"
  psk="$WIFI_PASS"
  key_mgmt=WPA-PSK
}
EOF
sudo ip link set wlan0 up
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf || true
sudo dhclient -v wlan0 || true

# 2) Робоча папка і конфіги медіасервера
mkdir -p "$WORKDIR" && cd "$WORKDIR"

cat > mediamtx.yml <<EOF
paths:
  cam1:
    source: publisher
    publishUser: ${RTSP_USER}
    publishPass: ${RTSP_PASS}
    readUser: ${RTSP_USER}
    readPass: ${RTSP_PASS}
  cam2:
    source: publisher
    publishUser: ${RTSP_USER}
    publishPass: ${RTSP_PASS}
    readUser: ${RTSP_USER}
    readPass: ${RTSP_PASS}

rtsp:
  protocols: [tcp]

http:
  address: :8080
EOF

cat > docker-compose.yml <<EOF
services:
  mediamtx:
    image: bluenviron/mediamtx:latest
    container_name: mediamtx
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./mediamtx.yml:/mediamtx.yml:ro
    entrypoint: ["/mediamtx"]
    command: ["/mediamtx.yml"]
EOF

# 3) Утиліта чеку медіасервера
sudo tee /usr/local/bin/wait_for_mediamtx.sh > /dev/null <<'EOF'
#!/bin/bash
TIMEOUT=\${1:-60}
for i in \$(seq 1 \$TIMEOUT); do
  (echo > /dev/tcp/127.0.0.1/8554) >/dev/null 2>&1 && exit 0
  sleep 1
done
exit 1
EOF
sudo chmod +x /usr/local/bin/wait_for_mediamtx.sh

# 4) Скрипт запуску ffmpeg (використовує libx264 як запасний варіант)
sudo tee /usr/local/bin/orangepi_cam_start.sh > /dev/null <<'EOF'
#!/bin/bash
DEV="\$1"
STREAM_NAME="\$2"
USER="\$3"
PASS="\$4"
LOG="/var/log/\${STREAM_NAME}.log"
mkdir -p /var/log
exec >> "\${LOG}" 2>&1
echo "=== Starting publisher for \${DEV} -> \${STREAM_NAME} at \$(date) ==="
for i in \$(seq 1 60); do
  (echo > /dev/tcp/127.0.0.1/8554) >/dev/null 2>&1 && break
  sleep 1
done
ENVFILE="/etc/orangepi_cam.conf"
if [ -f "\$ENVFILE" ]; then source "\$ENVFILE"; fi
# build ffmpeg command (use libx264)
CMD="/usr/bin/ffmpeg -hide_banner -loglevel info \
  -f v4l2 -input_format mjpeg -thread_queue_size 2048 -framerate \${CAM_FPS:-${CAM_FPS}} -video_size \${CAM_RES:-${CAM_RES}} \
  -probesize 5000000 -analyzeduration 5000000 -i \"\${DEV}\" \
  -an -c:v libx264 -preset ultrafast -tune zerolatency -r \${CAM_FPS:-${CAM_FPS}} -b:v \${CAM_BITRATE:-${CAM_BITRATE}} -maxrate \${CAM_BITRATE:-${CAM_BITRATE}} -bufsize 7000k \
  -fflags nobuffer -flags low_delay -rtsp_transport tcp -f rtsp \"rtsp://\${USER}:\${PASS}@127.0.0.1:8554/\${STREAM_NAME}\""
# retry loop
attempt=1
while true; do
  echo "ffmpeg attempt \$attempt at \$(date)"
  eval "\$CMD"
  rc=\$?
  if [ \$rc -eq 0 ]; then echo "ffmpeg exited normally"; break; fi
  echo "ffmpeg failed (rc=\$rc), sleeping \$((2**(attempt<6?attempt:6)))s"
  sleep \$((2**(attempt<6?attempt:6)))
  attempt=\$((attempt+1))
done
EOF
sudo chmod +x /usr/local/bin/orangepi_cam_start.sh

# 5) systemd юніти для двох камер
sudo tee /etc/systemd/system/cam1.service > /dev/null <<'EOF'
[Unit]
Description=Publish /dev/cam1 to MediaMTX cam1
After=network.target docker.service
Requires=network.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/wait_for_mediamtx.sh 60
ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam1 cam1 ${RTSP_USER} ${RTSP_PASS}
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/cam2.service > /dev/null <<'EOF'
[Unit]
Description=Publish /dev/cam2 to MediaMTX cam2
After=network.target docker.service
Requires=network.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/wait_for_mediamtx.sh 60
ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam2 cam2 ${RTSP_USER} ${RTSP_PASS}
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

# 6) Файл за замовчуванням для камер
sudo tee /etc/orangepi_cam.conf > /dev/null <<EOF
CAM_RES=${CAM_RES}
CAM_FPS=${CAM_FPS}
CAM_BITRATE=${CAM_BITRATE}
EOF
sudo chmod 644 /etc/orangepi_cam.conf

# 7) Контрольний інтерфейс (меню)
sudo tee /usr/local/bin/orangepi_control.sh > /dev/null <<'EOF'
#!/bin/bash
MEDIADIR="$HOME/orangepi-mediamtx"
menu(){ cat <<EOM
1) Change Wi-Fi
2) Change RTSP credentials
3) Change camera defaults
4) Start services
5) Stop services
6) Show status and IP
7) Exit
EOM
}
set_wifi(){ read -p "SSID: " SSID; read -s -p "Password: " PASS; echo; sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<W
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=UA
network={ ssid="\$SSID" psk="\$PASS" key_mgmt=WPA-PSK }
W
sudo ip link set wlan0 up; sudo wpa_cli -i wlan0 reconfigure || sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf; sudo dhclient -v wlan0 || true; ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I; }
set_rtsp_creds(){ read -p "RTSP user: " U; read -s -p "RTSP pass: " P; echo; sed -i "s/publishUser: .*/publishUser: ${U}/" ${MEDIADIR}/mediamtx.yml || true; sed -i "s/publishPass: .*/publishPass: ${P}/" ${MEDIADIR}/mediamtx.yml || true; sudo sed -i "s/ExecStart=.*cam1 .* .*/ExecStart=\/bin\/bash \/usr\/local\/bin\/orangepi_cam_start.sh \/dev\/cam1 cam1 ${U} ${P}/" /etc/systemd/system/cam1.service || true; sudo sed -i "s/ExecStart=.*cam2 .* .*/ExecStart=\/bin\/bash \/usr\/local\/bin\/orangepi_cam_start.sh \/dev\/cam2 cam2 ${U} ${P}/" /etc/systemd/system/cam2.service || true; sudo systemctl daemon-reload; echo "RTSP updated."; }
set_cam_defaults(){ read -p "Resolution (e.g. 1280x720): " R; read -p "FPS (e.g. 30): " F; read -p "Bitrate (e.g. 2000k): " B; sudo tee /etc/orangepi_cam.conf > /dev/null <<E
CAM_RES=\${R}
CAM_FPS=\${F}
CAM_BITRATE=\${B}
E
echo "Camera defaults updated."; }
start_services(){ cd ${WORKDIR} || true; sudo docker compose up -d; sudo systemctl daemon-reload; sudo systemctl enable --now cam1.service cam2.service; echo "Started."; }
stop_services(){ sudo systemctl stop cam1.service cam2.service; sudo docker compose down; echo "Stopped."; }
show_status(){ ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I; sudo ss -lntp | egrep '8554|8080' || true; sudo docker ps --filter name=mediamtx; sudo systemctl status cam1.service --no-pager || true; sudo systemctl status cam2.service --no-pager || true; }
while true; do menu; read -p "Choose [1-7]: " CH; case "$CH" in 1) set_wifi ;; 2) set_rtsp_creds ;; 3) set_cam_defaults ;; 4) start_services ;; 5) stop_services ;; 6) show_status ;; 7) exit 0 ;; *) echo "Invalid" ;; esac; done
EOF
sudo chmod +x /usr/local/bin/orangepi_control.sh

# 8) Запустити docker і сервіси
sudo systemctl daemon-reload
sudo systemctl enable cam1.service cam2.service
cd "$WORKDIR"
sudo docker compose pull || true
sudo docker compose up -d
sudo systemctl restart cam1.service cam2.service

echo "INSTALLER: done. Run 'sudo /usr/local/bin/orangepi_control.sh' to manage the system."
