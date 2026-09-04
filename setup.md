# ORANGE PI ZERO 3W CAM

Нижче один блок для вставки в PuTTY. Він виконується по порядку зверху вниз.

## Стабільні імена камер udev

Кожна камера OPENAICAM створює кілька відеоінтерфейсів. У вашій системі основні відеопристрої мають `index==0`, а metadata-інтерфейси не використовуються. Номери `/dev/videoN` можуть змінитися після перепідключення, тому сервіси працюватимуть через стабільні посилання `/dev/cam1` і `/dev/cam2`.

Виконайте цей блок у PuTTY після підключення обох камер:

```bash
sudo tee /etc/udev/rules.d/99-orangepi-cameras.rules > /dev/null <<'EOF'
# Orange Pi Zero 3W - fixed camera names
# CAM1 = xHCI USB port -> /dev/cam1
SUBSYSTEM=="video4linux", KERNEL=="video[0-9]*", KERNELS=="1-1:1.0", ATTR{name}=="OPENAICAM: OPENAICAM", ATTR{index}=="0", SYMLINK+="cam1", MODE="0666"

# CAM2 = EHCI USB port -> /dev/cam2
SUBSYSTEM=="video4linux", KERNEL=="video[0-9]*", KERNELS=="5-1:1.0", ATTR{name}=="OPENAICAM: OPENAICAM", ATTR{index}=="0", SYMLINK+="cam2", MODE="0666"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=video4linux
ls -l /dev/cam1 /dev/cam2
```

Очікуваний результат:

```text
/dev/cam1 -> /dev/video0
/dev/cam2 -> /dev/video2
```

`KERNELS=="1-1:1.0"` і `KERNELS=="5-1:1.0"` прив'язують камери до фізичних USB-портів, а не до змінних номерів `/dev/videoN`. `ATTR{index}=="0"` вибирає основний відеопотік і відсікає metadata-інтерфейси `/dev/video1` та `/dev/video3`.

Перевірити відповідність можна командами:

```bash
v4l2-ctl --list-devices
ls -l /dev/video* /dev/cam*
```

Після цього в конфігурації потоків треба використовувати саме `/dev/cam1` і `/dev/cam2`. Відключення однієї камери не повинно змінювати стабільне ім'я іншої.

## Встановлення і налаштування MediaMTX

MediaMTX — це легкий відеосервер, який приймає RTSP-потоки від `ffmpeg` і роздає їх AI-пристрою в локальній мережі. Він запускається в Docker-контейнері `mediamtx`, тому не потребує окремої ручної компіляції або встановлення бінарного файла на Orange Pi.

У цьому проєкті використовується така схема:

```text
/dev/cam1 -> ffmpeg -> MediaMTX -> rtsp://ORANGE_PI_IP:8554/cam1
/dev/cam2 -> ffmpeg -> MediaMTX -> rtsp://ORANGE_PI_IP:8554/cam2
```

### Встановлення Docker і запуск MediaMTX

Якщо Docker ще не встановлений, виконайте в PuTTY:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Після додавання користувача до групи Docker перелогіньтеся через PuTTY або виконайте `newgrp docker`.

Створіть каталог і конфігураційні файли MediaMTX:

```bash
mkdir -p ~/orangepi-mediamtx
cd ~/orangepi-mediamtx

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

sudo docker compose pull
sudo docker compose up -d
```

### Пояснення конфігурації

- `authInternalUsers` створює RTSP-користувача `user` з паролем `pass`. Змініть ці значення на власні.
- `cam1` і `cam2` — два іменовані RTSP-шляхи, які приймають публікацію від `ffmpeg`.
- `rtsp.protocols: [tcp]` використовує TCP, що зазвичай стабільніше за UDP через Wi-Fi.
- `network_mode: "host"` дозволяє MediaMTX слухати порти Orange Pi без окремого Docker NAT.
- порт `8554` використовується для RTSP, порт `8080` зарезервований під HTTP/API MediaMTX.
- поле `version:` навмисно відсутнє, оскільки сучасний Docker Compose вважає його застарілим.

### Перевірка MediaMTX

```bash
cd ~/orangepi-mediamtx
sudo docker compose ps
sudo docker logs mediamtx --tail 100
sudo ss -lntp | grep -E '8554|8080' || true
```

Очікувано контейнер має статус `Up`, а порт `8554` має слухати на Orange Pi. Після запуску MediaMTX systemd-сервіси `cam1.service` і `cam2.service` публікують у нього потоки з `/dev/cam1` і `/dev/cam2`.

RTSP-адреси для AI-пристрою:

```text
rtsp://user:pass@192.168.4.1:8554/cam1
rtsp://user:pass@192.168.4.1:8554/cam2
```

Замість `192.168.4.1` використовуйте актуальну IP-адресу Orange Pi, якщо AI-пристрій підключений до іншої мережі.

## Короткий чек‑ліст відновлення

```bash
cd ~/orangepi-mediamtx && sudo sed -i '/^version:/d' docker-compose.yml
sudo bash -c 'cat > /etc/orangepi_cam.conf <<EOF
CAM_RES=1280x720
CAM_FPS=30
CAM_BITRATE=2000k
EOF'
sudo chmod 644 /etc/orangepi_cam.conf
sudo systemctl daemon-reload
sudo systemctl restart cam1.service cam2.service
cd ~/orangepi-mediamtx && sudo docker compose pull || true && sudo docker compose up -d
sudo tail -n 80 /var/log/cam1.log
ip -4 addr show wlan0 | grep -oP "(?<=inet\s)\d+(\.\d+){3}" || hostname -I
```

Пояснення:
- перший рядок прибирає застаріле поле `version:` з `docker-compose.yml`;
- другий блок задає стабільні параметри камер `1280x720 @ 30fps / 2000k`;
- `systemctl restart` перезапускає ffmpeg-публікації;
- `docker compose up -d` піднімає або оновлює MediaMTX;
- `tail` показує логи для перевірки стану;
- остання команда показує IP пристрою в мережі.

Після цього можна знову перевірити RTSP-адреси і статус сервісів.

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
authInternalUsers:
  users:
    - user: ${RTSP_USER}
      password: ${RTSP_PASS}

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
ENCODER_MODE="${CAM_ENCODER:-auto}"
HW_DEVICE="${CAM_HW_DEVICE:-/dev/video11}"
ENCODER_ARGS=(-c:v libx264 -preset ultrafast -tune zerolatency)
if [[ "$ENCODER_MODE" == "hardware" || "$ENCODER_MODE" == "auto" ]] && [[ -e "$HW_DEVICE" ]] && /usr/bin/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_v4l2m2m' && /usr/bin/ffmpeg -hide_banner -loglevel error -f lavfi -i color=size=16x16:rate=1 -frames:v 1 -c:v h264_v4l2m2m -f null - >/dev/null 2>&1; then
  ENCODER_ARGS=(-c:v h264_v4l2m2m)
  echo "Using hardware encoder h264_v4l2m2m on $HW_DEVICE"
else
  [[ "$ENCODER_MODE" == "hardware" ]] && echo "Hardware encoder unavailable; using libx264"
fi
CMD=(/usr/bin/ffmpeg -hide_banner -loglevel info -f v4l2 -input_format mjpeg -thread_queue_size 2048 -framerate "$FPS" -video_size "$RES" -probesize 5000000 -analyzeduration 5000000 -i "$DEV" -an "${ENCODER_ARGS[@]}" -r "$FPS" -b:v "$BR" -maxrate "$BR" -bufsize 7000k -fflags nobuffer -flags low_delay -rtsp_transport tcp -f rtsp "rtsp://${USER}:${PASS}@127.0.0.1:8554/${STREAM_NAME}")
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
set_rtsp_creds(){ read -p "RTSP user: " U; read -s -p "RTSP pass: " P; echo; sed -i "s#^\s*user: .*#    user: ${U}#" "$MEDIADIR/mediamtx.yml" || true; sed -i "s#^\s*password: .*#      password: ${P}#" "$MEDIADIR/mediamtx.yml" || true; sudo sed -i "s#^ExecStart=.*cam1 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam1 cam1 ${U} ${P}#" /etc/systemd/system/cam1.service || true; sudo sed -i "s#^ExecStart=.*cam2 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam2 cam2 ${U} ${P}#" /etc/systemd/system/cam2.service || true; sudo systemctl daemon-reload; echo "RTSP updated."; }
set_rtsp_creds(){ read -p "RTSP user: " U; read -s -p "RTSP pass: " P; echo; sed -i "s#^\s*user: .*#    user: ${U}#" "$MEDIADIR/mediamtx.yml" || true; sed -i "s#^\s*password: .*#      password: ${P}#" "$MEDIADIR/mediamtx.yml" || true; sudo sed -i "s#^ExecStart=.*cam1 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam1 cam1 ${U} ${P}#" /etc/systemd/system/cam1.service || true; sudo sed -i "s#^ExecStart=.*cam2 .*#ExecStart=/bin/bash /usr/local/bin/orangepi_cam_start.sh /dev/cam2 cam2 ${U} ${P}#" /etc/systemd/system/cam2.service || true; sudo systemctl daemon-reload; echo "RTSP updated."; }
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

