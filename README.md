# ORANGE-PI-ZERO-3W-CAM
Короткий проєкт для headless розгортання RTSP-потоків з двох USB‑камер на Orange Pi Zero 3W за допомогою MediaMTX, ffmpeg, Docker і systemd. Включає інсталяторний блок, systemd‑юнити, скрипти запуску, udev‑правила для стабільних імен камер і набір пресетів для швидкої зміни якості.
Overview
Короткий проєкт для headless розгортання RTSP-потоків з двох USB‑камер на Orange Pi Zero 3W за допомогою MediaMTX, ffmpeg, Docker і systemd. Включає інсталяторний блок, systemd‑юнити, скрипти запуску, udev‑правила для стабільних імен камер і набір пресетів для швидкої зміни якості.

Requirements
Пристрій: Orange Pi Zero 3W з SSH доступом.

Підключення: інтернет для apt і Docker; USB‑камери підключені.

Права: користувач з sudo.

Пакети: docker, docker-compose-plugin, ffmpeg, v4l-utils, wpa_supplicant.

Quick Install
Вставте цей блок у PuTTY цілком (замінивши YOUR_SSID і YOUR_WIFI_PASS), він створить всі файли і запустить сервіси.

bash
# Заміни WIFI_SSID і WIFI_PASS перед запуском
WIFI_SSID="YOUR_SSID"
WIFI_PASS="YOUR_WIFI_PASS"
# Скопіюй і встав весь інсталяторний блок з інструкції, який ви вже маєте
# (цей блок створює mediamtx.yml, docker-compose.yml, скрипти, systemd юніти, /etc/orangepi_cam.conf)
Після завершення виконайте:

bash
sudo systemctl daemon-reload
sudo systemctl enable --now cam1.service cam2.service
cd ~/orangepi-mediamtx && sudo docker compose up -d
WiFi Setup
Створення конфігурації без редактора:

bash
sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=UA

network={
  ssid="YOUR_SSID"
  psk="YOUR_WIFI_PASS"
  key_mgmt=WPA-PSK
}
EOF
sudo ip link set wlan0 up
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf || true
sudo dhclient -v wlan0 || true
ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
Порада: якщо затримка SSH велика, вставляйте блоки цілими, не відкривайте редактор.

USB Device Binding and V4L2
Створити стабільні імена камер

Дізнатися ідентифікатори:

bash
lsusb
udevadm info -a -p $(udevadm info -q path -n /dev/video0)
Правило udev (підставте idVendor/idProduct або serial):

bash
sudo tee /etc/udev/rules.d/99-usb-cam.rules > /dev/null <<'EOF'
SUBSYSTEM=="video4linux", ATTRS{idVendor}=="1bcf", ATTRS{idProduct}=="2b8a", SYMLINK+="cam1", MODE="0666"
SUBSYSTEM=="video4linux", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="0825", SYMLINK+="cam2", MODE="0666"
EOF
sudo udevadm control --reload
sudo udevadm trigger
ls -l /dev/cam1 /dev/cam2 || ls -l /dev/video*
Налаштування формату і FPS

bash
sudo apt install -y v4l-utils
sudo v4l2-ctl -d /dev/cam1 --set-fmt-video=width=1280,height=720,pixelformat=MJPG
sudo v4l2-ctl -d /dev/cam1 --set-parm=30
v4l2-ctl -d /dev/cam1 --all
Config Presets Control Troubleshooting and Access
Файл пресетів

bash
sudo tee /etc/orangepi_cam_presets.conf > /dev/null <<'EOF'
default;1280x720;30;2000k
high;1920x1080;30;3500k
low;1280x720;15;1200k
EOF
Застосувати пресет

bash
PRESET=default
grep "^${PRESET};" /etc/orangepi_cam_presets.conf | awk -F';' '{print $2 > "/tmp/_res"; print $3 > "/tmp/_fps"; print $4 > "/tmp/_br"}'
RES=$(cat /tmp/_res); FPS=$(cat /tmp/_fps); BR=$(cat /tmp/_br)
sudo tee /etc/orangepi_cam.conf > /dev/null <<EOL
CAM_RES=${RES}
CAM_FPS=${FPS}
CAM_BITRATE=${BR}
EOL
sudo systemctl restart cam1.service cam2.service
Швидкі перевірки і логи

bash
sudo tail -n 80 /var/log/cam1.log
sudo docker logs mediamtx --tail 200
sudo ss -lntp | egrep '8554|8080' || true
ps aux | egrep 'ffmpeg|orangepi_cam_start' --color=auto
Типові проблеми

hw encoder not found — скрипт використовує libx264 за замовчуванням; для hw перевірте ffmpeg -encoders.

Broken pipe / drop frames — зменшіть CAM_RES, CAM_FPS або CAM_BITRATE.

Docker compose no configuration file provided — виконуйте docker compose у папці з docker-compose.yml.

Адреси потоків

Код
rtsp://user:pass@127.0.0.1:8554/cam1
rtsp://user:pass@<ORANGE_PI_IP>:8554/cam1
