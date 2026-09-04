# ORANGE PI ZERO 3W CAM

Нижче один блок для вставки в PuTTY. Він виконується по порядку зверху вниз.

1) Спочатку замініть свої дані: `YOUR_SSID` і `YOUR_WIFI_PASS`.
2) Після вставки весь блок виконується автоматично.
3) Якщо програма попросить введення з клавіатури, вводьте значення і натискайте Enter.
4) Не відкривайте редактор у терміналі — вставляйте блок цілком.

```bash
set -e
WIFI_SSID="YOUR_SSID"
WIFI_PASS="YOUR_WIFI_PASS"
RTSP_USER="user"
RTSP_PASS="pass"
CAM_RES="1280x720"
CAM_FPS="30"
CAM_BITRATE="2000k"
WORKDIR="$HOME/orangepi-mediamtx"

# Блок 1: оновлення системи и встановлення пакетів
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget ca-certificates gnupg lsb-release apt-transport-https iproute2 net-tools wireless-tools wpa_supplicant dhclient ffmpeg

# Блок 2: встановлення Docker і docker-compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo apt install -y docker-compose-plugin
newgrp docker || true

# Блок 3: налаштування Wi‑Fi
# Тут вже вставлені SSID і пароль з верхніх рядків.
sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=UA
network={
  ssid="$WIFI_SSID"
  psk="$WIFI_PASS"
  key_mgmt=WPA-PSK
}
EOF
sudo ip link set wlan0 up || true
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf || true
sudo dhclient -v wlan0 || true

# Блок 4: створення папки, медіасервера і конфігів
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

# Блок 5: чекер готовності MediaMTX
sudo tee /usr/local/bin/wait_for_mediamtx.sh > /dev/null <<'EOF'
#!/bin/bash
TIMEOUT="${1:-60}"
for i in $(seq 1 "$TIMEOUT"); do
  (echo > /dev/tcp/127.0.0.1/8554) >/dev/null 2>&1 && exit 0
  sleep 1
done
exit 1
EOF
sudo chmod +x /usr/local/bin/wait_for_mediamtx.sh

# Блок 6: запуск ffmpeg для камер
# Цей блок створює скрипт, який буде запускати потік з /dev/cam1 та /dev/cam2.
sudo tee /usr/local/bin/orangepi_cam_start.sh > /dev/null <<'EOF'
#!/bin/bash
set -u
DEV="${1:-}"
STREAM_NAME="${2:-}"
USER="${3:-}"
PASS="${4:-}"
LOG="/var/log/${STREAM_NAME}.log"
mkdir -p /var/log
exec >> "${LOG}" 2>&1
for i in $(seq 1 60); do
  (echo > /dev/tcp/127.0.0.1/8554) >/dev/null 2>&1 && break
  sleep 1
done
ENVFILE="/etc/orangepi_cam.conf"
if [ -f "$ENVFILE" ]; then . "$ENVFILE"; fi
RES="${CAM_RES:-1280x720}"
FPS="${CAM_FPS:-30}"
BR="${CAM_BITRATE:-2000k}"
CMD=(/usr/bin/ffmpeg -hide_banner -loglevel info -f v4l2 -input_format mjpeg -thread_queue_size 2048 -framerate "$FPS" -video_size "$RES" -probesize 5000000 -analyzeduration 5000000 -i "$DEV" -an -c:v libx264 -preset ultrafast -tune zerolatency -r "$FPS" -b:v "$BR" -maxrate "$BR" -bufsize 7000k -fflags nobuffer -flags low_delay -rtsp_transport tcp -f rtsp "rtsp://${USER}:${PASS}@127.0.0.1:8554/${STREAM_NAME}")
while true; do
  "${CMD[@]}"
  rc=$?
  [ "$rc" -eq 0 ] && break
  sleep 2
done
EOF
sudo chmod +x /usr/local/bin/orangepi_cam_start.sh

# Блок 7: systemd-сервіси cam1 і cam2
# Вони запускають потоки автоматично після старту системи.
sudo tee /etc/systemd/system/cam1.service > /dev/null <<EOF
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
sudo tee /etc/systemd/system/cam2.service > /dev/null <<EOF
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

# Блок 8: параметри за замовчуванням для камер
sudo tee /etc/orangepi_cam.conf > /dev/null <<EOF
CAM_RES=${CAM_RES}
CAM_FPS=${CAM_FPS}
CAM_BITRATE=${CAM_BITRATE}
EOF
sudo chmod 644 /etc/orangepi_cam.conf

# Блок 9: меню керування
# Якщо потрібно змінити Wi‑Fi, логін/пароль RTSP або якість — запускайте:
# sudo /usr/local/bin/orangepi_control.sh
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
network={ ssid="${SSID}" psk="${PASS}" key_mgmt=WPA-PSK }
W
sudo ip link set wlan0 up; sudo wpa_cli -i wlan0 reconfigure || sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf; sudo dhclient -v wlan0 || true; ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I; }
set_rtsp_creds(){ read -p "RTSP user: " U; read -s -p "RTSP pass: " P; echo; sed -i "s#publishUser: .*#publishUser: ${U}#" "$MEDIADIR/mediamtx.yml" || true; sed -i "s#publishPass: .*#publishPass: ${P}#" "$MEDIADIR/mediamtx.yml" || true; sudo sed -i "s#^ExecStart=.*cam1 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam1 cam1 ${U} ${P}#" /etc/systemd/system/cam1.service || true; sudo sed -i "s#^ExecStart=.*cam2 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam2 cam2 ${U} ${P}#" /etc/systemd/system/cam2.service || true; sudo systemctl daemon-reload; echo "RTSP updated."; }
set_cam_defaults(){ read -p "Resolution (e.g. 1280x720): " R; read -p "FPS (e.g. 30): " F; read -p "Bitrate (e.g. 2000k): " B; sudo tee /etc/orangepi_cam.conf > /dev/null <<E
CAM_RES=${R}
CAM_FPS=${F}
CAM_BITRATE=${B}
E
echo "Camera defaults updated."; }
start_services(){ cd "$MEDIADIR" || true; sudo docker compose up -d; sudo systemctl daemon-reload; sudo systemctl enable --now cam1.service cam2.service; echo "Started."; }
stop_services(){ sudo systemctl stop cam1.service cam2.service; sudo docker compose down; echo "Stopped."; }
show_status(){ ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I; sudo ss -lntp | grep -E '8554|8080' || true; sudo docker ps --filter name=mediamtx || true; sudo systemctl status cam1.service --no-pager || true; sudo systemctl status cam2.service --no-pager || true; }
while true; do menu; read -p "Choose [1-7]: " CH; case "$CH" in 1) set_wifi ;; 2) set_rtsp_creds ;; 3) set_cam_defaults ;; 4) start_services ;; 5) stop_services ;; 6) show_status ;; 7) exit 0 ;; *) echo "Invalid" ;; esac; done
EOF
sudo chmod +x /usr/local/bin/orangepi_control.sh

# Блок 10: завершення установки
sudo systemctl daemon-reload
sudo systemctl enable cam1.service cam2.service || true
cd "$WORKDIR"
sudo docker compose up -d || true
sudo systemctl restart cam1.service cam2.service || true

echo "Installer complete. Run: sudo /usr/local/bin/orangepi_control.sh"
```

Пояснення по введенню:
- У рядках `WIFI_SSID="YOUR_SSID"` і `WIFI_PASS="YOUR_WIFI_PASS"` треба вставити свій Wi‑Fi.
- Якщо в терміналі з’явиться запит на введення, вводьте потрібне значення і натискайте Enter.
- Не змінюйте порядок блоків: вони виконуються зверху вниз.
- Після завершення можна перевірити стан:

```bash
ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
sudo ss -lntp | egrep '8554|8080' || true
sudo docker logs mediamtx --tail 200
```

RTSP адреси:

```text
rtsp://user:pass@127.0.0.1:8554/cam1
rtsp://user:pass@127.0.0.1:8554/cam2
```

