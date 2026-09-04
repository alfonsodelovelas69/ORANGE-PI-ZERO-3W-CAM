# ORANGE PI ZERO 3W CAM

## Зміст
- [Опис проєкту](#опис-проєкту)
- [Вимоги](#вимоги)
- [Швидкий старт](#швидкий-старт)
- [Структура проєкту](#структура-проєкту)
- [Розгортання через PuTTY](#розгортання-через-putty)
- [Після встановлення](#після-встановлення)
- [Робота з камерами](#робота-з-камерами)
- [Зміна якості відео](#зміна-якості-відео)
- [Типові проблеми](#типові-проблеми)
- [Адреси RTSP](#адреси-rtsp)
- [Корисні команди](#корисні-команди)

Повний headless проєкт для запуску двох USB-камер на Orange Pi Zero 3W з RTSP-потоками через MediaMTX, ffmpeg, Docker і systemd.

Проєкт дозволяє:
- підключати Orange Pi до Wi‑Fi без графічного інтерфейсу;
- запускати два відео-потоки через MediaMTX;
- автоматично піднімати ffmpeg-перетворення в systemd;
- керувати параметрами Wi‑Fi, RTSP і якістю відео без редагування в текстовому редакторі;
- повторно відтворювати інсталяцію через PuTTY або SSH.

<a id="опис-проєкту"></a>
## Опис проєкту

Цей проєкт створює повну headless-інсталяцію для Orange Pi Zero 3W. Він:
- налаштовує Wi‑Fi через `/etc/wpa_supplicant/wpa_supplicant.conf`;
- створює каталог `~/orangepi-mediamtx` з конфігурацією MediaMTX;
- піднімає Docker-контейнер `bluenviron/mediamtx:latest`;
- запускає два `ffmpeg`-потоки в systemd для `cam1` і `cam2`;
- зберігає параметри якості у `/etc/orangepi_cam.conf`;
- надає інтерфейс керування через `/usr/local/bin/orangepi_control.sh`.

<a id="вимоги"></a>
## Вимоги

- Orange Pi Zero 3W з SSH доступом через PuTTY або terminal;
- доступ до інтернету для `apt` і Docker;
- стабільне живлення 5V;
- увімкнені USB-камери;
- користувач з правами `sudo`.

Необхідні пакети:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget ca-certificates gnupg lsb-release apt-transport-https \
  iproute2 net-tools wireless-tools wpa_supplicant dhclient ffmpeg docker-compose-plugin
```

<a id="швидкий-старт"></a>
## Швидкий старт

Після копіювання файлів проєкту в папку на Orange Pi виконайте:

```bash
chmod +x installer.sh orangepi_control.sh orangepi_cam_start.sh
WIFI_SSID="YOUR_SSID" WIFI_PASS="YOUR_WIFI_PASS" bash ./installer.sh
```

Якщо хочете змінити значення після установки, відкрийте:

```bash
sudo /usr/local/bin/orangepi_control.sh
```

<a id="структура-проєкту"></a>
## Структура проєкту

```text
ORANGE-PI-ZERO-3W-CAM/
├── README.md
├── installer.sh
├── docker-compose.yml
├── mediamtx.yml
├── orangepi_cam_start.sh
├── orangepi_control.sh
├── .gitignore
└── .git/
```

### Опис файлів

- `installer.sh` — головний інсталятор, який створює Wi‑Fi, робочий каталог, конфіг MediaMTX, systemd юніти, файли підписки ffmpeg і control-скрипт.
- `docker-compose.yml` — конфігурація контейнера MediaMTX.
- `mediamtx.yml` — налаштування шляхів `cam1` і `cam2`.
- `orangepi_cam_start.sh` — скрипт запуску ffmpeg для кожної камери.
- `orangepi_control.sh` — меню управління Wi‑Fi, RTSP, стартом/зупинкою сервісів.
- `.gitignore` — стандартні файли для виключення логів і тимчасових даних.

<a id="розгортання-через-putty"></a>
## Розгортання через PuTTY

### 1. Підготовка системи

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget ca-certificates gnupg lsb-release apt-transport-https \
  iproute2 net-tools wireless-tools wpa_supplicant dhclient ffmpeg
```

### 2. Встановлення Docker

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo apt install -y docker-compose-plugin
newgrp docker || true
```

### 3. Перенесіть проєкт на Orange Pi

Ви можете скопіювати каталог через `scp` або просто зберегти ці файли на пристрої.

Наприклад:

```bash
scp -r /path/to/ORANGE-PI-ZERO-3W-CAM orangepi@192.168.1.50:/home/orangepi/
```

### 4. Запуск інсталятора

```bash
cd ~/ORANGE-PI-ZERO-3W-CAM
chmod +x installer.sh orangepi_control.sh orangepi_cam_start.sh
WIFI_SSID="YOUR_SSID" WIFI_PASS="YOUR_WIFI_PASS" bash ./installer.sh
```

> Для headless режиму важливо вставляти блоки цілими командами, не відкривати редактор у терміналі, щоб не втратити з’єднання через затримку.

<a id="після-встановлення"></a>
## Після встановлення

Перевірка інтернету і IP:

```bash
ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
```

Перевірка сервісів:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cam1.service cam2.service
sudo systemctl status cam1.service --no-pager
sudo systemctl status cam2.service --no-pager
```

Запуск MediaMTX вручну:

```bash
cd ~/orangepi-mediamtx
sudo docker compose up -d
```

<a id="робота-з-камерами"></a>
## Робота з камерами

### Перевірка доступних пристроїв

```bash
ls -l /dev/video*
```

### Створення стабільних імен

```bash
lsusb
udevadm info -a -p $(udevadm info -q path -n /dev/video0)
```

Пример правила udev:

```bash
sudo tee /etc/udev/rules.d/99-usb-cam.rules > /dev/null <<'EOF'
SUBSYSTEM=="video4linux", ATTRS{idVendor}=="1bcf", ATTRS{idProduct}=="2b8a", SYMLINK+="cam1", MODE="0666"
SUBSYSTEM=="video4linux", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="0825", SYMLINK+="cam2", MODE="0666"
EOF
sudo udevadm control --reload
sudo udevadm trigger
ls -l /dev/cam1 /dev/cam2 || ls -l /dev/video*
```

### Налаштування V4L2

```bash
sudo apt install -y v4l-utils
sudo v4l2-ctl -d /dev/cam1 --set-fmt-video=width=1280,height=720,pixelformat=MJPG
sudo v4l2-ctl -d /dev/cam1 --set-parm=30
v4l2-ctl -d /dev/cam1 --all
```

<a id="зміна-якості-відео"></a>
## Зміна якості відео

Файл `/etc/orangepi_cam.conf` відповідає за якість:

```bash
sudo bash -c 'cat > /etc/orangepi_cam.conf <<EOF
CAM_RES=1280x720
CAM_FPS=30
CAM_BITRATE=2000k
EOF'
```

Після зміни конфігу перезапустіть сервіси:

```bash
sudo systemctl daemon-reload
sudo systemctl restart cam1.service cam2.service
```

<a id="типові-проблеми"></a>
## Типові проблеми

### 1. `no configuration file provided`

Причина: команда `docker compose` виконується не в тій директорії.

Рішення:

```bash
cd ~/orangepi-mediamtx
sudo docker compose up -d
```

### 2. `hw encoder not found`

Скрипт у проєкті використовує `libx264` за замовчуванням. Якщо потрібно апаратне кодування, перевіряйте доступні кодеки:

```bash
ffmpeg -encoders | grep -i h264
```

### 3. `Broken pipe` або пропуски кадрів

Зменшіть якість:

```bash
sudo bash -c 'cat > /etc/orangepi_cam.conf <<EOF
CAM_RES=1280x720
CAM_FPS=20
CAM_BITRATE=1500k
EOF'
sudo systemctl restart cam1.service cam2.service
```

### 4. Потік не піднімається

Перевірте логи:

```bash
sudo tail -n 80 /var/log/cam1.log
sudo docker logs mediamtx --tail 200
sudo journalctl -u cam1.service -n 80 --no-pager
```

<a id="адреси-rtsp"></a>
## Адреси RTSP

Локально на Orange Pi:

```text
rtsp://user:pass@127.0.0.1:8554/cam1
rtsp://user:pass@127.0.0.1:8554/cam2
```

По Wi‑Fi в локальній мережі:

```text
rtsp://user:pass@192.168.1.50:8554/cam1
rtsp://user:pass@192.168.1.50:8554/cam2
```

Де:
- `user` і `pass` — RTSP логін/пароль;
- `192.168.1.50` — IP вашого Orange Pi.

<a id="корисні-команди"></a>
## Корисні команди

```bash
# IP пристрою
ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I

# статус сервісів
sudo systemctl status cam1.service --no-pager
sudo systemctl status cam2.service --no-pager

# логи ffmpeg
sudo tail -n 80 /var/log/cam1.log
sudo tail -n 80 /var/log/cam2.log

# логи MediaMTX
sudo docker logs mediamtx --tail 200

# перевірка портів
sudo ss -lntp | egrep '8554|8080' || true

# перевірка процесів
ps aux | egrep 'ffmpeg|orangepi_cam_start' --color=auto
```

## Коротка інструкція для повторення

1. Встановити базові пакети.
2. Встановити Docker і docker-compose-plugin.
3. Скопіювати проєкт у домашню папку Orange Pi.
4. Запустити інсталятор:

```bash
cd ~/ORANGE-PI-ZERO-3W-CAM
chmod +x installer.sh orangepi_control.sh orangepi_cam_start.sh
WIFI_SSID="YOUR_SSID" WIFI_PASS="YOUR_WIFI_PASS" bash ./installer.sh
```

5. Перевірити статус сервіса.
6. Підключитися через VLC або інший RTSP-клієнт.

## Підсумок

Ця структура дозволяє повторити проєкт з нуля на Orange Pi Zero 3W без графічного інтерфейсу. Усі основні компоненти зібрані у файли проєкту і доступні для повторного використання в автоматизованому режимі.

Для керування використовуються:

```bash
sudo /usr/local/bin/orangepi_control.sh
```

Інструкція готова до копіювання в PuTTY і повторного виконання на новому пристрої.
