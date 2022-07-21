# Rename Node Proxmox - Tested on Proxmox 7.x

```sh
# set nama host lama ke .ini file
echo "HOSTNAME_LAMA=$(hostname)" > ~/pmrename.ini

# set nama hostbaru
echo "HOSTNAME_BARU=NAMA-BARUNYA" >> ~/pmrename.ini

# get variable
source <(grep = ~/pmrename.ini)

# edit file hostnamenya
sed -i.bak "s/$HOSTNAME_LAMA/$HOSTNAME_BARU/gi" /etc/hostname

# edit file hostname
sed -i.bak "s/$HOSTNAME_LAMA/$HOSTNAME_BARU/gi" /etc/hosts

# edit mail
[ -e "/etc/mailname" ] && sed -i.bak "s/$HOSTNAME_LAMA/$HOSTNAME_BARU/gi" /etc/mailname

# edit main.cf
[ -e "/etc/postfix/main.cf" ] && sed -i.bak "s/$HOSTNAME_LAMA/$HOSTNAME_BARU/gi" /etc/postfix/main.cf

# copy config ke nama node baru
cp "/var/lib/rrdcached/db/pve2-node/$HOSTNAME_LAMA" "/var/lib/rrdcached/db/pve2-node/$HOSTNAME_BARU" -r

cp "/var/lib/rrdcached/db/pve2-storage/$HOSTNAME_LAMA" "/var/lib/rrdcached/db/pve2-storage/$HOSTNAME_BARU" -r

cp "/var/lib/rrdcached/db/pve2-$HOSTNAME_LAMA" "/var/lib/rrdcached/db/pve2-$HOSTNAME_BARU" -r

reboot now
```

## Command Setelah Reboot

```sh

# get variable
source <(grep = ~/pmrename.ini)
# update config storage
sed -i.bak "s/nodes $HOSTNAME_LAMA/nodes $HOSTNAME_BARU/gi" /etc/pve/storage.cfg

mv /etc/pve/nodes/$HOSTNAME_LAMA/qemu-server/*.conf /etc/pve/nodes/$HOSTNAME_BARU/qemu-server/

mv /etc/pve/nodes/$HOSTNAME_LAMA/lxc/*.conf /etc/pve/nodes/$HOSTNAME_BARU/lxc/

# cek Proxmox Dashboard UI nya error atau ngga, kalo ngga kebuka berarti error xixi..
```

## Clear Up

```sh

# Pastikan tidak ada error pada tahapan di atas
# cek vm, storage, dll.

# Clear Up
source <(grep = ~/pmrename.ini)

rm /etc/hostname.bak && rm /etc/hosts.bak

[ -e "/etc/mailname.bak" ] && rm /etc/mailname.bak

[ -e "/etc/postfix/main.cf.bak" ] && rm /etc/postfix/main.cf.bak

rm /var/lib/rrdcached/db/pve2-node/$HOSTNAME_LAMA -r

rm /var/lib/rrdcached/db/pve2-storage/$HOSTNAME_LAMA -r

rm /var/lib/rrdcached/db/pve2-$HOSTNAME_LAMA -r

rm /etc/pve/nodes/$HOSTNAME_LAMA -r

rm /etc/pve/storage.cfg.bak

rm ~/pmrename.ini
```

[Refensi Acuan](https://pve.proxmox.com/wiki/Renaming_a_PVE_node)