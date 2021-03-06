#!/bin/bash

# Handle self referencing, sourcing etc.
if [[ $0 != $BASH_SOURCE ]]; then
  export CMD=$BASH_SOURCE
else
  export CMD=$0
fi

# Ensure a consistent working directory so relative paths work.
pushd `dirname $CMD` > /dev/null
BASE=`pwd -P`
popd > /dev/null
cd $BASE
# git diff -U0 -w --no-color FILE

# Enable NFSv3 over UDP.
# [ "`nfsconf --get nfsd udp`" != "y" ] && sudo nfsconf --set nfsd udp y

#sudo firewall-cmd --quiet --zone=libvirt --query-service=nfs || sudo firewall-cmd --zone=libvirt --add-service=nfs
#sudo firewall-cmd --quiet --zone=libvirt --query-service=nfs3 || sudo firewall-cmd --zone=libvirt --add-service=nfs3
# sudo firewall-cmd --quiet --zone=libvirt --query-service=mountd || sudo firewall-cmd --zone=libvirt --add-service=mountd
# sudo firewall-cmd --quiet --zone=libvirt --query-service=rpc-bind || sudo firewall-cmd --zone=libvirt --add-service=rpc-bind

# Cleanup.
[ -d $BASE/android/ ] sudo umount $BASE/android/ &>/dev/null
vagrant destroy -f &>/dev/null ; rm -rf $BASE/apk/ $BASE/android/

set -e

# Create virtual machines..
vagrant up --provider=virtualbox

# virsh --connect qemu:///system shutdown --domain proxy_centos_vpn
virsh --connect qemu:///system shutdown --domain proxy_debian_vpn
virsh --connect qemu:///system shutdown --domain proxy_debian_build

for i in {1..10}; do
  [ "`virsh --connect qemu:///system list --state-running --name | wc -l`" == "2" ] && break
  sleep 1
done

# virt-xml --connect qemu:///system proxy_centos_vpn --quiet --edit --disk /var/lib/libvirt/images/proxy_centos_vpn.img,discard=unmap,detect_zeroes=unmap,cache=unsafe,io=threads,bus=scsi,target=sda,address.type=drive,address.controller=0,address.bus=0,address.target=0,address.unit=0
virt-xml --connect qemu:///system proxy_debian_vpn --quiet --edit --disk /var/lib/libvirt/images/proxy_debian_vpn.img,discard=unmap,detect_zeroes=unmap,cache=unsafe,io=threads,bus=scsi,target=sda,address.type=drive,address.controller=0,address.bus=0,address.target=0,address.unit=0
virt-xml --connect qemu:///system proxy_debian_build --quiet --edit --disk /var/lib/libvirt/images/proxy_debian_build.img,discard=unmap,detect_zeroes=unmap,cache=unsafe,io=threads,bus=scsi,target=sda,address.type=drive,address.controller=0,address.bus=0,address.target=0,address.unit=0

# virt-xml --connect qemu:///system proxy_centos_vpn --quiet --edit scsi --controller type=scsi,model=virtio-scsi --print-diff
virt-xml --connect qemu:///system proxy_debian_vpn --quiet --edit scsi --controller type=scsi,model=virtio-scsi
virt-xml --connect qemu:///system proxy_debian_build --quiet --edit scsi --controller type=scsi,model=virtio-scsi

# virsh --connect qemu:///system start --domain proxy_centos_vpn
virsh --connect qemu:///system start --domain proxy_debian_vpn
virsh --connect qemu:///system start --domain proxy_debian_build

sleep 30

# Upload the scripts.
vagrant upload centos-8-vpnweb.sh vpnweb.sh centos_vpn &> /dev/null
vagrant upload centos-8-openvpn.sh openvpn.sh centos_vpn &> /dev/null
vagrant upload debian-10-vpnweb.sh vpnweb.sh debian_vpn &> /dev/null
vagrant upload debian-10-openvpn.sh openvpn.sh debian_vpn &> /dev/null

vagrant upload debian-10-build-setup.sh setup.sh debian_build &> /dev/null
vagrant upload debian-10-build.sh build.sh debian_build &> /dev/null

vagrant ssh -c 'chmod +x vpnweb.sh openvpn.sh' centos_vpn &> /dev/null
vagrant ssh -c 'chmod +x vpnweb.sh openvpn.sh' debian_vpn &> /dev/null
vagrant ssh -c 'chmod +x setup.sh build.sh' debian_build &> /dev/null

# Provision the VPN service.
vagrant ssh --tty -c 'sudo --login bash -e < vpnweb.sh' centos_vpn
vagrant ssh --tty -c 'sudo --login bash -e < openvpn.sh' centos_vpn
vagrant ssh --tty -c 'sudo --login bash -e < vpnweb.sh' debian_vpn
vagrant ssh --tty -c 'sudo --login bash -e < openvpn.sh' debian_vpn

# Compile the Android client.
vagrant ssh --tty -c 'bash -ex setup.sh' debian_build
vagrant ssh --tty -c 'bash -ex build.sh' debian_build

# Extract the Android APKs from the build environment.
[ -d $BASE/apk/ ] && rm --force --recursive $BASE/apk/ ; mkdir $BASE/apk/
vagrant ssh-config debian_build > $BASE/apk/config
printf "cd /home/vagrant/bitmask_android_leap/app/build/outputs\nget -r apk\n" | sftp -F $BASE/apk/config debian_build

# Download Termux
[ -d $BASE/apk/termux/ ] && rm --force --recursive $BASE/apk/termux/ ; mkdir --parents $BASE/apk/termux/
curl --silent --location --output $BASE/apk/termux/com.termux_106.apk https://f-droid.org/repo/com.termux_106.apk
printf "b28e4dac0707655c6d8d22abaf45338029ce434086e3d88b64bdee1e84c04ec3  $BASE/apk/termux/com.termux_106.apk" | sha256sum -c || exit 1

curl --silent --location --output $BASE/apk/termux/com.termux.api_47.apk https://f-droid.org/repo/com.termux.api_47.apk
printf "086b8d7f098cee431bfac615213eae2e2cbb44f6f2543ee38a12e0f36b3098f8  $BASE/apk/termux/com.termux.api_47.apk" | sha256sum -c || exit 1

curl --silent --location --output $BASE/apk/termux/com.termux.widget_11.apk https://f-droid.org/repo/com.termux.widget_11.apk
printf "934cfb004993348d207ad3e21928e94fba07cb8185ba292ab5209eab09c15dcc  $BASE/apk/termux/com.termux.widget_11.apk" | sha256sum -c || exit 1

# Download the OpenVPN Android GUI
[ -d $BASE/apk/openvpn/ ] && rm --force --recursive $BASE/apk/openvpn/ ; mkdir --parents $BASE/apk/openvpn/
curl --silent --location --output $BASE/apk/openvpn/de.blinkt.openvpn_175.apk https://f-droid.org/repo/de.blinkt.openvpn_175.apk
printf "359dd465e81c796c98f9cb4deb493956715c5834ebf31b643f366dcf6a713037  $BASE/apk/openvpn/de.blinkt.openvpn_175.apk" | sha256sum -c || exit 1


[ ! -d $BASE/android/ ] && mkdir $BASE/android/
sshfs vagrant@192.168.221.50:/home/vagrant/bitmask_android_leap android -o uidfile=1000 -o gidfile=1000 \
-o StrictHostKeyChecking=no -o IdentityFile=$BASE/.vagrant/machines/debian_build/libvirt/private_key
