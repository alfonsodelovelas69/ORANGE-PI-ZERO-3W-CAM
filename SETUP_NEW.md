# ORANGE PI ZERO 3W CAM — Ручна установка

> ⚠️ **ВАЖЛИВО:** Якщо ви хочете швидку й просту установку, використовуйте **`README.md`** та запустіть `installer.sh`.  
> Цей файл для досвідчених користувачів, які хочуть встановити проект вручну крок за кроком.

---

## 📋 Послідовність кроків

### **Етап 1: Оновлення системи** (обов'язково)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget ca-certificates gnupg lsb-release apt-transport-https \
  iproute2 net-tools wireless-tools wpa_supplicant dhclient ffmpeg v4l-utils
```

### **Етап 2: Встановлення Docker** (обов'язково)

**Метод A: Рекомендований (через oficial Docker)**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker "$USER"
sudo apt install -y docker-compose-plugin
newgrp docker || true
```

**Метод B: Через apt (простіший)**
```bash
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker || true
```

Перевірка:
```bash
docker --version
docker compose version
```

### **Етап 3: Налаштування Wi-Fi** (обов'язково)

```bash
sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=UA

network={
  ssid="YOUR_SSID"
  psk="YOUR_PASSWORD"
  key_mgmt=WPA-PSK
}
EOF

# Замініть YOUR_SSID і YOUR_PASSWORD на ваші дані
```

Активація:
```bash
sudo ip link set wlan0 up || true
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf || true
sudo dhclient -v wlan0 || true
```

Перевірка:
```bash
ip -4 addr show wlan0
```

### **Етап 4: Стабільні імена для камер** (опціонально, але рекомендується)

> Цей етап робить імена `/dev/cam1` та `/dev/cam2` фіксованими, щоб вони не змінювалися після перепідключення.

**Крок 1: Знайдіть USB-адреси камер**

Підключіть обидві камери й виконайте:
```bash
lsusb
udevadm info -a -p $(udevadm info -q path -n /dev/video0)
```

Запишіть значення `KERNELS` для кожної камери.

**Крок 2: Створіть правило udev**

```bash
sudo tee /etc/udev/rules.d/99-orangepi-cameras.rules > /dev/null <<'EOF'
# Orange Pi Zero 3W - fixed camera names
# Замініть KERNELS на значення з вашої системи
SUBSYSTEM=="video4linux", KERNELS=="1-1:1.0", ATTR{index}=="0", SYMLINK+="cam1", MODE="0666"
SUBSYSTEM=="video4linux", KERNELS=="5-1:1.0", ATTR{index}=="0", SYMLINK+="cam2", MODE="0666"
EOF
```

**Крок 3: Перезавантажте правила**

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=video4linux
```

**Крок 4: Перевірте**

```bash
ls -l /dev/cam1 /dev/cam2
# Очікуваний результат: симлінки на /dev/videoX
```

### **Етап 5: Створення каталогу MediaMTX** (обов'язково)

```bash
mkdir -p ~/orangepi-mediamtx
cd ~/orangepi-mediamtx
```

### **Етап 6: Конфігурація MediaMTX** (обов'язково)

```bash
cat > mediamtx.yml <<'EOF'
authInternalUsers:
  users:
    - user: user
      password: pass

paths:
  cam1:
    source: publisher
  cam2:
    source: publisher

rtsp:
  protocols: [tcp]

http:
  address: :8080
EOF
```

### **Етап 7: Docker Compose конфіг** (обов'язково)

```bash
cat > docker-compose.yml <<'EOF'
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
```

### **Етап 8: Запуск MediaMTX** (обов'язково)

```bash
sudo docker compose pull
sudo docker compose up -d
```

Перевірка:
```bash
sudo docker ps | grep mediamtx
sudo docker logs mediamtx --tail 50
```

### **Етап 9: Скрипт очікування MediaMTX** (обов'язково)

```bash
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
```

### **Етап 10: Скрипт запуску FFmpeg** (обов'язково)

```bash
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

echo "=== Starting publisher for ${DEV} -> ${STREAM_NAME} at $(date) ==="
for i in $(seq 1 60); do
  (echo > /dev/tcp/127.0.0.1/8554) >/dev/null 2>&1 && break
  sleep 1
done

ENVFILE="/etc/orangepi_cam.conf"
if [ -f "$ENVFILE" ]; then
  source "$ENVFILE"
fi

RES="${CAM_RES:-1280x720}"
FPS="${CAM_FPS:-30}"
BR="${CAM_BITRATE:-2000k}"
ENCODER_MODE="${CAM_ENCODER:-auto}"
HW_DEVICE="${CAM_HW_DEVICE:-/dev/video11}"

ENCODER_ARGS=(-c:v libx264 -preset ultrafast -tune zerolatency)
if [[ "$ENCODER_MODE" == "hardware" || "$ENCODER_MODE" == "auto" ]] \
  && [[ -e "$HW_DEVICE" ]] \
  && /usr/bin/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_v4l2m2m' \
  && /usr/bin/ffmpeg -hide_banner -loglevel error -f lavfi -i color=size=16x16:rate=1 \
      -frames:v 1 -c:v h264_v4l2m2m -f null - >/dev/null 2>&1; then
  ENCODER_ARGS=(-c:v h264_v4l2m2m)
  echo "Using hardware encoder h264_v4l2m2m on $HW_DEVICE"
else
  [[ "$ENCODER_MODE" == "hardware" ]] && echo "Hardware encoder unavailable; using libx264"
fi

CMD=(
  /usr/bin/ffmpeg
  -hide_banner
  -loglevel info
  -f v4l2
  -input_format mjpeg
  -thread_queue_size 2048
  -framerate "$FPS"
  -video_size "$RES"
  -probesize 5000000
  -analyzeduration 5000000
  -i "$DEV"
  -an
  "${ENCODER_ARGS[@]}"
  -r "$FPS"
  -b:v "$BR"
  -maxrate "$BR"
  -bufsize 7000k
  -fflags nobuffer
  -flags low_delay
  -rtsp_transport tcp
  -f rtsp
  "rtsp://${USER}:${PASS}@127.0.0.1:8554/${STREAM_NAME}"
)

attempt=1
while true; do
  echo "ffmpeg attempt $attempt at $(date)"
  "${CMD[@]}"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ffmpeg exited normally"
    break
  fi
  echo "ffmpeg failed (rc=${rc}), sleeping $((2**(attempt<6?attempt:6)))s"
  sleep $((2**(attempt<6?attempt:6)))
  attempt=$((attempt + 1))
done
EOF

sudo chmod +x /usr/local/bin/orangepi_cam_start.sh
```

### **Етап 11: Systemd сервіси** (обов'язково)

**Сервіс для cam1:**
```bash
sudo tee /etc/systemd/system/cam1.service > /dev/null <<'EOF'
[Unit]
Description=Publish /dev/cam1 to MediaMTX cam1
After=network.target docker.service
Requires=network.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/wait_for_mediamtx.sh 60
ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam1 cam1 user pass
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF
```

**Сервіс для cam2:**
```bash
sudo tee /etc/systemd/system/cam2.service > /dev/null <<'EOF'
[Unit]
Description=Publish /dev/cam2 to MediaMTX cam2
After=network.target docker.service
Requires=network.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/wait_for_mediamtx.sh 60
ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam2 cam2 user pass
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF
```

### **Етап 12: Конфіг якості** (обов'язково)

```bash
sudo tee /etc/orangepi_cam.conf > /dev/null <<'EOF'
CAM_RES=1280x720
CAM_FPS=30
CAM_BITRATE=2000k
EOF

sudo chmod 644 /etc/orangepi_cam.conf
```

### **Етап 13: Меню управління** (обов'язково)

```bash
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
set_wifi(){
  read -p "SSID: " SSID
  read -s -p "Password: " PASS
  echo
  sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<W
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=UA
network={ ssid="${SSID}" psk="${PASS}" key_mgmt=WPA-PSK }
W
  sudo ip link set wlan0 up
  sudo wpa_cli -i wlan0 reconfigure || sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
  sudo dhclient -v wlan0 || true
  ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
}
set_rtsp_creds(){
  read -p "RTSP user: " U
  read -s -p "RTSP pass: " P
  echo
  sed -i "s#^\s*user: .*#    user: ${U}#" "$MEDIADIR/mediamtx.yml" || true
  sed -i "s#^\s*password: .*#      password: ${P}#" "$MEDIADIR/mediamtx.yml" || true
  sudo sed -i "s#^ExecStart=.*cam1 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam1 cam1 ${U} ${P}#" /etc/systemd/system/cam1.service || true
  sudo sed -i "s#^ExecStart=.*cam2 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam2 cam2 ${U} ${P}#" /etc/systemd/system/cam2.service || true
  sudo systemctl daemon-reload
  echo "RTSP updated."
}
set_cam_defaults(){
  read -p "Resolution (e.g. 1280x720): " R
  read -p "FPS (e.g. 30): " F
  read -p "Bitrate (e.g. 2000k): " B
  sudo tee /etc/orangepi_cam.conf > /dev/null <<E
CAM_RES=${R}
CAM_FPS=${F}
CAM_BITRATE=${B}
E
  echo "Camera defaults updated."
}
start_services(){
  cd "$MEDIADIR" || true
  sudo docker compose up -d
  sudo systemctl daemon-reload
  sudo systemctl enable --now cam1.service cam2.service
  echo "Started."
}
stop_services(){
  sudo systemctl stop cam1.service cam2.service
  cd "$MEDIADIR" && sudo docker compose down
  echo "Stopped."
}
show_status(){
  echo "=== IP Address ==="
  ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
  echo ""
  echo "=== Listening Ports ==="
  sudo ss -lntp | grep -E '8554|8080' || true
  echo ""
  echo "=== Docker Containers ==="
  sudo docker ps --filter name=mediamtx || true
  echo ""
  echo "=== Service Status ==="
  sudo systemctl status cam1.service --no-pager || true
  sudo systemctl status cam2.service --no-pager || true
}
while true; do
  menu
  read -p "Choose [1-7]: " CH
  case "$CH" in
    1) set_wifi ;;
    2) set_rtsp_creds ;;
    3) set_cam_defaults ;;
    4) start_services ;;
    5) stop_services ;;
    6) show_status ;;
    7) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
EOF

sudo chmod +x /usr/local/bin/orangepi_control.sh
```

### **Етап 14: Запуск сервісів** (обов'язково)

```bash
sudo systemctl daemon-reload
sudo systemctl enable cam1.service cam2.service
sudo systemctl start cam1.service cam2.service
```

Перевірка:
```bash
sudo systemctl status cam1.service --no-pager
sudo systemctl status cam2.service --no-pager
sudo docker logs mediamtx --tail 50
```

---

## ✅ Завершення

Якщо все пройшло успішно:

1. **Отримайте IP-адресу:**
   ```bash
   ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
   ```

2. **Перевірте RTSP-адреси:**
   ```
   rtsp://user:pass@192.168.x.x:8554/cam1
   rtsp://user:pass@192.168.x.x:8554/cam2
   ```

3. **Прослухайте логи:**
   ```bash
   sudo tail -f /var/log/cam1.log
   ```

---

## 🔄 Швидка переустановка

Якщо щось пішло не так, повертаєтесь до **README.md** й запустіть `installer.sh`:

```bash
cd ~/ORANGE-PI-ZERO-3W-CAM
WIFI_SSID="YOUR_SSID" WIFI_PASS="YOUR_WIFI_PASS" bash ./installer.sh
```

---

**Версія:** 1.0  
**Останнє оновлення:** 2026-09-04
