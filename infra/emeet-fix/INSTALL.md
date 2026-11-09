# eMeet 자동 복구 설치 (root 필요)

sudo cp $HOME/emeet-fix/99-emeet.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=328f

# usbreset을 비밀번호 없이 쓰려면:
echo "$USER ALL=(root) NOPASSWD: /usr/bin/usbreset" | sudo tee /etc/sudoers.d/emeet-usbreset
sudo chmod 440 /etc/sudoers.d/emeet-usbreset

systemctl --user daemon-reload
