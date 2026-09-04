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
  sed -i "s#publishUser: .*#publishUser: ${U}#" "$MEDIADIR/mediamtx.yml" || true
  sed -i "s#publishPass: .*#publishPass: ${P}#" "$MEDIADIR/mediamtx.yml" || true
  sed -i "s#readUser: .*#readUser: ${U}#" "$MEDIADIR/mediamtx.yml" || true
  sed -i "s#readPass: .*#readPass: ${P}#" "$MEDIADIR/mediamtx.yml" || true
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
  sudo docker compose down
  echo "Stopped."
}
show_status(){
  ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I
  sudo ss -lntp | grep -E '8554|8080' || true
  sudo docker ps --filter name=mediamtx || true
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
