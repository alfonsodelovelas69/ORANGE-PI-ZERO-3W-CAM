# ORANGE PI ZERO 3W CAM

**Повний headless проєкт** для запуску двох USB-камер на Orange Pi Zero 3W з RTSP-потоками через MediaMTX, ffmpeg, Docker і systemd.

## 📋 Зміст
- [Швидкий старт (3 кроки)](#швидкий-старт-3-кроки)
- [Опис проєкту](#опис-проєкту)
- [Вимоги](#вимоги)
- [Детальні інструкції](#детальні-інструкції)
- [Робота з камерами](#робота-з-камерами)
- [Зміна якості відео](#зміна-якості-відео)
- [Типові проблеми](#типові-проблеми)
- [Корисні команди](#корисні-команди)

---

## ⚡ Швидкий старт (3 кроки)

### Крок 1: Копіюйте файли на Orange Pi
```bash
scp -r /path/to/ORANGE-PI-ZERO-3W-CAM orangepi@192.168.1.50:/home/orangepi/
```

### Крок 2: Підключіться через SSH/PuTTY
```bash
ssh orangepi@192.168.1.50
# або через PuTTY
```

### Крок 3: Запустіть встановлювач
```bash
cd ~/ORANGE-PI-ZERO-3W-CAM
chmod +x installer.sh orangepi_control.sh orangepi_cam_start.sh
WIFI_SSID="YOUR_SSID" WIFI_PASS="YOUR_WIFI_PASS" bash ./installer.sh
```

**Готово!** Інсталятор зробить все автоматично:
- ✅ Оновить систему й встановить пакети
- ✅ Встановить Docker
- ✅ Налаштує Wi-Fi
- ✅ Запустить MediaMTX
- ✅ Налаштує ffmpeg для обох камер

Після завершення проект готовий до роботи.

---

## 📝 Опис проєкту

Цей проєкт створює **повну headless-інсталяцію** для Orange Pi Zero 3W без графічного інтерфейсу. Він:

- **Wi-Fi** — налаштовує автоматичне підключення без екрана
- **MediaMTX** — легкий відеосервер у Docker для RTSP-потоків
- **FFmpeg** — кодує відео з обох USB-камер і передає до MediaMTX
- **Systemd** — автоматично запускає ffmpeg при старті системи
- **Управління** — меню для змін Wi-Fi, логіна/пароля, якості без редактора

Схема потоків:
```
/dev/cam1 → ffmpeg → MediaMTX → rtsp://192.168.x.x:8554/cam1
/dev/cam2 → ffmpeg → MediaMTX → rtsp://192.168.x.x:8554/cam2
```

---

## 📦 Вимоги

**Апаратура:**
- Orange Pi Zero 3W з SSH доступом
- 2x USB-камери OPENAICAM (або подібні)
- Wi-Fi модуль (вбудований)
- Стабільне живлення 5V

**Програмне забезпечення:**
- Користувач з правами `sudo`
- Доступ в Інтернет для завантаження пакетів

**Відсутні на системі за замовчуванням:**
- Docker & docker-compose
- FFmpeg
- Необхідні системні пакети

Все встановлюється автоматично через `installer.sh`.

---

## 🔧 Детальні інструкції

### 0. Підготовка (якщо система нова)

Якщо це новий Orange Pi, підключіть з терміналу чи PuTTY й оновіть систему:

```bash
sudo apt update && sudo apt upgrade -y
```

### 1. Завантажте проєкт

**Спосіб A: через SCP (рекомендується)**
```bash
scp -r ORANGE-PI-ZERO-3W-CAM orangepi@192.168.1.50:/home/orangepi/
```

**Спосіб B: вручну через SFTP**
Завантажте ZIP-файл проєкту й розпакуйте на пристрій.

**Спосіб C: через Git**
```bash
cd /home/orangepi
git clone https://github.com/your-repo/ORANGE-PI-ZERO-3W-CAM.git
cd ORANGE-PI-ZERO-3W-CAM
```

### 2. Запустіть інсталятор

```bash
cd ~/ORANGE-PI-ZERO-3W-CAM
chmod +x installer.sh orangepi_control.sh orangepi_cam_start.sh

# Встановіть Wi-Fi SSID і пароль
WIFI_SSID="your_network_name" WIFI_PASS="your_password" bash ./installer.sh
```

> **Важливо!** Замініть `your_network_name` та `your_password` на реальні дані вашої мережі Wi-Fi.

### 3. Перевірте результат

```bash
# Отримайте IP-адресу
ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I

# Перевірте MediaMTX
sudo docker ps | grep mediamtx

# Перевірте ffmpeg-сервіси
sudo systemctl status cam1.service --no-pager
sudo systemctl status cam2.service --no-pager
```

### 4. Тестуйте RTSP-адреси

Використовуйте будь-який RTSP-плеєр (VLC, FFplay тощо):

```
rtsp://user:pass@192.168.x.x:8554/cam1
rtsp://user:pass@192.168.x.x:8554/cam2
```

Замініть `192.168.x.x` на IP-адресу вашого Orange Pi (з кроку 3).

---

## 📹 Робота з камерами

### Перевірка підключених камер

```bash
# Список всіх V4L2-пристроїв
ls -l /dev/video*

# Детальна інформація про камери
v4l2-ctl --list-devices
```

### Стабільні імена для камер

За замовчуванням `/dev/videoN` можуть змінюватися після перезавантаження. Для фіксованих імен `/dev/cam1` та `/dev/cam2`:

```bash
# Знайдіть USB-bus ID камер
udevadm info -a -p $(udevadm info -q path -n /dev/video0)

# Створіть правило udev
sudo tee /etc/udev/rules.d/99-orangepi-cameras.rules > /dev/null <<'EOF'
# Замініть KERNELS на реальні значення з команди вище
SUBSYSTEM=="video4linux", KERNELS=="1-1:1.0", ATTR{index}=="0", SYMLINK+="cam1", MODE="0666"
SUBSYSTEM=="video4linux", KERNELS=="5-1:1.0", ATTR{index}=="0", SYMLINK+="cam2", MODE="0666"
EOF

# Перезавантажте правила
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=video4linux

# Перевірте
ls -l /dev/cam1 /dev/cam2
```

Після цього перезапустіть сервіси:
```bash
sudo systemctl restart cam1.service cam2.service
```

### Налаштування V4L2 параметрів

```bash
# Встановіть роздільну здатність і формат
sudo v4l2-ctl -d /dev/cam1 --set-fmt-video=width=1280,height=720,pixelformat=MJPG

# Встановіть FPS
sudo v4l2-ctl -d /dev/cam1 --set-parm=30

# Перевірте всі параметри
v4l2-ctl -d /dev/cam1 --all
```

---

## 🎬 Зміна якості відео

Якість контролюється файлом `/etc/orangepi_cam.conf`:

### Через меню (рекомендується)

```bash
sudo /usr/local/bin/orangepi_control.sh
# Виберіть "3) Change camera defaults"
```

### Вручну через конфіг

```bash
sudo nano /etc/orangepi_cam.conf
```

Параметри:
- `CAM_RES` — роздільна здатність (1280x720, 1920x1080 тощо)
- `CAM_FPS` — кадри за секунду (15, 20, 30)
- `CAM_BITRATE` — бітрейт (1000k, 2000k, 5000k)

Приклади:

**Висока якість (жадіб ресурси):**
```
CAM_RES=1920x1080
CAM_FPS=30
CAM_BITRATE=5000k
```

**Стандартна якість (рекомендується):**
```
CAM_RES=1280x720
CAM_FPS=30
CAM_BITRATE=2000k
```

**Низька якість (слабке Wi-Fi):**
```
CAM_RES=640x480
CAM_FPS=15
CAM_BITRATE=1000k
```

Після змін перезапустіть сервіси:

```bash
sudo systemctl restart cam1.service cam2.service
```

---

## 🆘 Типові проблеми

### 1. "`command not found: docker`"
**Рішення:** Інсталятор не завершився успішно або Docker не встановлений.
```bash
# Перевірте, чи запущений інсталятор
sudo systemctl status cam1.service
# Якщо помилка — перезапустіть інсталятор
bash ./installer.sh
```

### 2. "`no configuration file provided`"
**Рішення:** Команда виконується не в правильній директорії.
```bash
cd ~/orangepi-mediamtx
sudo docker compose up -d
```

### 3. "`Broken pipe` або пропуски кадрів"
**Рішення:** Зменшіть якість або бітрейт.
```bash
sudo nano /etc/orangepi_cam.conf
# Змініть на нижчі значення
sudo systemctl restart cam1.service cam2.service
```

### 4. "`hw encoder not found`"
**Причина:** Апаратне кодування недоступне.
**Рішення:** Використовується програмне кодування (libx264) — це нормально.
```bash
# Перевірте логи
sudo tail -f /var/log/cam1.log
```

### 5. "Wi-Fi не підключається"
**Перевірка:**
```bash
sudo wpa_cli -i wlan0 status
sudo systemctl restart wpa_supplicant
ip -4 addr show wlan0
```

**Рішення:** Змініть Wi-Fi через меню:
```bash
sudo /usr/local/bin/orangepi_control.sh
# Виберіть "1) Change Wi-Fi"
```

### 6. "`RTP packets are too big`"
**Причина:** Пакети RTSP занадто великі.
**Рішення:** Це попередження, але для стабільності зменшіть якість:
```bash
CAM_RES=1280x720  # замість 1920x1080
CAM_BITRATE=2000k  # замість вищого
```

---

## 💡 Корисні команди

### Перевірка IP-адреси
```bash
ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
```

### Перевірка портів
```bash
sudo ss -lntp | grep -E '8554|8080'
```

### Логи ffmpeg
```bash
sudo tail -f /var/log/cam1.log
sudo tail -f /var/log/cam2.log
```

### Логи MediaMTX
```bash
sudo docker logs mediamtx -f --tail 50
```

### Перезапуск всіх сервісів
```bash
sudo systemctl restart cam1.service cam2.service
cd ~/orangepi-mediamtx && sudo docker compose restart
```

### Зупинка всіх сервісів
```bash
sudo systemctl stop cam1.service cam2.service
cd ~/orangepi-mediamtx && sudo docker compose down
```

### Запуск сервісів
```bash
sudo systemctl start cam1.service cam2.service
cd ~/orangepi-mediamtx && sudo docker compose up -d
```

### Меню управління
```bash
sudo /usr/local/bin/orangepi_control.sh
```

Опції:
1. Змінити Wi-Fi
2. Змінити RTSP логін/пароль
3. Змінити якість камер
4. Запустити сервіси
5. Зупинити сервіси
6. Показати статус і IP
7. Вихід

---

## 📁 Структура проєкту

```text
ORANGE-PI-ZERO-3W-CAM/
├── README.md                     # Ця документація
├── setup.md                      # Альтернативна ручна установка
├── installer.sh                  # Головний скрипт установки
├── docker-compose.yml            # Docker конфігурація
├── mediamtx.yml                  # MediaMTX конфігурація
├── orangepi_cam_start.sh         # FFmpeg запуск (копіюється в /usr/local/bin/)
├── orangepi_control.sh           # Меню управління (копіюється в /usr/local/bin/)
└── .gitignore                    # Git ignore файл
```

---

## 🔐 Безпека

**За замовчуванням:**
- RTSP логін: `user`
- RTSP пароль: `pass`

**Змініть обов'язково!**
```bash
sudo /usr/local/bin/orangepi_control.sh
# Виберіть "2) Change RTSP credentials"
```

Використовуйте складні пароли, якщо пристрій доступний з Інтернету.

---

## 📞 Підтримка

Якщо виникають проблеми:

1. **Перевірте логи:**
   ```bash
   sudo tail /var/log/cam1.log
   sudo docker logs mediamtx
   ```

2. **Перезапустіть все:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart cam1.service cam2.service
   cd ~/orangepi-mediamtx && sudo docker compose restart
   ```

3. **Переустановіть:**
   ```bash
   bash ./installer.sh
   ```

---

**Версія:** 1.0  
**Останнє оновлення:** 2026-09-04  
**Ліцензія:** MIT
