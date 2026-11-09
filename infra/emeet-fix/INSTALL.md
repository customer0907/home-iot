# eMeet 자동 복구 설치 (root 필요)

sudo cp /home/infrun42/emeet-fix/99-emeet.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=328f

# usbreset을 비밀번호 없이 쓰려면:
echo 'infrun42 ALL=(root) NOPASSWD: ***REDACTED***
sudo chmod 440 /etc/sudoers.d/emeet-usbreset

systemctl --user daemon-reload
