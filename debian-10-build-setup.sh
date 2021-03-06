#!/bin/bash

sudo tee /etc/modprobe.d/nested.conf <<-EOF > /dev/null
options kvm_intel nested=1
EOF
sudo tee /etc/sysctl.d/50-inotify.conf <<-EOF > /dev/null
fs.inotify.max_user_watches = 100000
user.max_inotify_watches = 100000
EOF

sudo sysctl -p --system
sudo sed -i "s/1024/3072/g" /etc/default/haveged
sudo sed -i "s/ENABLED=.*/ENABLED=\"true\"/g" /etc/default/sysstat
sudo systemctl restart haveged && sudo systemctl restart sysstat

# Point us at the development environment.
sudo tee --append /etc/hosts <<-EOF
192.168.221.146 api.debian.local
192.168.221.142 vpn.debian.local
192.168.221.142 142.vpn.debian.local
192.168.221.143 143.vpn.debian.local
192.168.221.144 144.vpn.debian.local
192.168.221.145 145.vpn.debian.local

192.168.221.246 api.centos.local
192.168.221.242 vpn.centos.local
192.168.221.242 242.vpn.centos.local
192.168.221.243 243.vpn.centos.local
192.168.221.244 244.vpn.centos.local
192.168.221.245 245.vpn.centos.local
EOF

# Create a swap file.
sudo dd if=/dev/zero of=/swap bs=1M count=12384
sudo chmod 600 /swap
sudo mkswap /swap
sudo swapoff --all
sudo sed -i "s/swap    sw/swap    pri=1,discard,sw/g" /etc/fstab
sudo tee -a /etc/fstab <<-EOF > /dev/null
# Swap file added to avoid out of memory crashes.
/swap       none    swap    pri=10,discard,sw      0       0
EOF
sudo swapon --all

# Trim the drive to free space.
sudo sed -i "s/OnCalendar.*/OnCalendar=hourly/g" /lib/systemd/system/fstrim.timer
sudo sed -i "s/AccuracySec.*/AccuracySec=5m/g" /lib/systemd/system/fstrim.timer
sudo systemctl daemon-reload && sudo systemctl enable fstrim.timer

# swap swap defaults
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

sudo apt-get -qq -y update && sudo apt-get -qq -y install git rsync ruby ruby-dev ruby-bundler openssl rake make bzip2 zlib1g-dev openssh-client default-jdk make gcc file unzip gnupg software-properties-common lib32z1 lib32stdc++6 haveged libcanberra-gtk-module libcanberra-gtk3-module packagekit-gtk3-module qemu-kvm qemu qemu-user-static vm sysfsutils meld gnutls-bin dnsutils net-tools nload nfs-kernel-server apt-file bash-completion bash-builtins < /dev/null > /dev/null

# Android client build.
cd $HOME

# Remove history limits.
sed -i "/HISTCONTROL/d" $HOME/.bashrc
sed -i "/HISTFILESIZE/d" $HOME/.bashrc
sed -i "s/HISTSIZE=.*/export HISTSIZE=100000/g" $HOME/.bashrc

# Setup NFS share
sudo tee -a /etc/exports <<-EOF > /dev/null
/home/vagrant/bitmask_android_leap 192.168.221.1(rw,async,no_subtree_check,anonuid=1000,anongid=1000)
EOF

[ ! -d /home/vagrant/bitmask_android_leap ] && mkdir /home/vagrant/bitmask_android_leap
sudo systemctl enable nfs-server && sudo systemctl start nfs-server

# Install Atom editor.
curl --location --silent https://packagecloud.io/AtomEditor/atom/gpgkey | sudo apt-key add -
export GNUPGHOME=$(mktemp -d /tmp/gnupg-XXXXXX)
[ "`gpg --quiet --no-options --keyring /etc/apt/trusted.gpg --list-keys 0A0FAB860D48560332EFB581B75442BBDE9E3B09 | wc -l`" != "5" ] && exit 1
rm --force --recursive $GNUPGHOME
sudo add-apt-repository --yes 'deb [arch=amd64] https://packagecloud.io/AtomEditor/atom/any/ any main'
sudo apt-get -qq -y update && sudo apt-get -qq -y install atom < /dev/null > /dev/null

mkdir $HOME/.atom/
cat <<-EOF > $HOME/.atom/config.cson
"*":
  core:
    autoHideMenuBar: true
    telemetryConsent: "no"
  editor:
    atomicSoftTabs: false
    defaultFontSize: 16
    fontSize: 16
    maxScreenLineLength: 1000
    showIndentGuide: true
    showInvisibles: true
  "exception-reporting":
    userId: "1b012ae8-7202-4b35-8d00-74c601e90fc1"
  welcome:
    showOnStartup: false
  whitespace:
    removeTrailingWhitespace: false
    ensureSingleTrailingNewline: false
EOF

# Install JDK v8
curl --location --silent https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | sudo apt-key add -
export GNUPGHOME=$(mktemp -d /tmp/gnupg-XXXXXX)
[ "`gpg --quiet --no-options --keyring /etc/apt/trusted.gpg --list-keys 8ED17AF5D7E675EB3EE3BCE98AC3B29174885C03 | wc -l`" != "5" ] && exit 1
rm --force --recursive $GNUPGHOME
sudo add-apt-repository --yes 'deb [arch=amd64] https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/ buster main'
sudo apt-get -qq -y update && sudo apt-get -qq -y install adoptopenjdk-8-hotspot < /dev/null > /dev/null

sudo update-alternatives --set java /usr/lib/jvm/adoptopenjdk-8-hotspot-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/adoptopenjdk-8-hotspot-amd64/bin/javac

# Update the apt-file cache.
sudo apt-file update &> /dev/null

# Install the Android command line tools.
curl --silent --show-error --location --output $HOME/commandlinetools-linux-6858069_latest.zip https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip
printf "87f6dcf41d4e642e37ba03cb2e387a542aa0bd73cb689a9e7152aad40a6e7a08  $HOME/commandlinetools-linux-6858069_latest.zip" | sha256sum -c || exit 1
sudo unzip -qq $HOME/commandlinetools-linux-6858069_latest.zip -d /opt/ && sudo mv /opt/cmdline-tools/ /opt/android-cmdline-tools/ && rm --force $HOME/commandlinetools-linux-6858069_latest.zip

[ -d /opt/android-sdk-linux/ ] && sudo rm --force --recursive /opt/android-sdk-linux/
yes | sudo sudo /opt/android-cmdline-tools/bin/sdkmanager --sdk_root=/opt/android-sdk-linux/ --licenses > /dev/null

sudo /opt/android-cmdline-tools/bin/sdkmanager --sdk_root=/opt/android-sdk-linux/ --install \
"extras;google;m2repository" "extras;android;m2repository" "cmdline-tools;latest" \
"ndk;21.3.6528147" "cmake;3.10.2.4988404" "build-tools;30.0.3" "platforms;android-30"

# The alternatve install command.
# sudo /opt/android-cmdline-tools/bin/sdkmanager --sdk_root=/opt/android-sdk-linux/ --install \
# "extras;google;simulators" "extras;google;webdriver" \
# "extras;google;m2repository" "extras;android;m2repository" \
# "cmdline-tools;latest" "ndk;21.3.6528147" "cmake;3.10.2.4988404" "skiaparser;1" \
# "build-tools;23.0.3" "build-tools;24.0.3" "build-tools;25.0.3" "build-tools;26.0.3" \
# "build-tools;27.0.3" "build-tools;28.0.3" "build-tools;29.0.3" "build-tools;30.0.3" \
# "platforms;android-23" "platforms;android-24" "platforms;android-25" "platforms;android-26" \
# "platforms;android-27" "platforms;android-28" "platforms;android-29" "platforms;android-30" \
# "system-images;android-26;default;x86" "system-images;android-26;default;x86_64" \
# "system-images;android-26;google_apis;x86" "system-images;android-26;google_apis_playstore;x86" \
# "system-images;android-27;default;x86" "system-images;android-27;default;x86_64" \
# "system-images;android-27;google_apis;x86" "system-images;android-27;google_apis_playstore;x86" \
# "system-images;android-28;default;x86" "system-images;android-28;default;x86_64" \
# "system-images;android-28;google_apis;x86" "system-images;android-28;google_apis;x86_64" \
# "system-images;android-28;google_apis_playstore;x86" "system-images;android-28;google_apis_playstore;x86_64" \
# "system-images;android-29;default;x86" "system-images;android-29;default;x86_64" \
# "system-images;android-29;google_apis;x86" "system-images;android-29;google_apis;x86_64" \
# "system-images;android-29;google_apis_playstore;x86" "system-images;android-29;google_apis_playstore;x86_64" \
# "system-images;android-30;google_apis;x86" "system-images;android-30;google_apis;x86_64" \
# "system-images;android-30;google_apis_playstore;x86" "system-images;android-30;google_apis_playstore;x86_64"

sudo /opt/android-cmdline-tools/bin/sdkmanager --sdk_root=/opt/android-sdk-linux/ --list_installed | awk -F' ' '{print $1}' | tail -n +4

[ -f /usr/lib/android-sdk/platform-tools/adb ] && sudo update-alternatives --install /usr/bin/adb adb /usr/lib/android-sdk/platform-tools/adb 10

sudo update-alternatives --install /usr/bin/adb adb /opt/android-sdk-linux/platform-tools/adb 20
sudo update-alternatives --install /usr/bin/emulator emulator /opt/android-sdk-linux/emulator/emulator 20
sudo update-alternatives --install /usr/bin/sdkmanager sdkmanager /opt/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager 20
sudo update-alternatives --install /usr/bin/avdmanager avdmanager /opt/android-sdk-linux/cmdline-tools/latest/bin/avdmanager 20

sudo tee /opt/android-sdk-linux/analytics.settings <<-EOF > /dev/null
{"userId":"00d88208-fba6-4128-bcab-43ea24471a29","hasOptedIn":false,"debugDisablePublishing":true,"saltValue":252009482191130365845997296475239957800466822540021702098,"saltSkew":666}
EOF

sudo chmod 664 /opt/android-sdk-linux/analytics.settings
HUMAN=$USER sudo --preserve-env=HUMAN sh -c 'chown $HUMAN:$HUMAN /opt/android-sdk-linux/analytics.settings'
# HUMAN=$USER sudo --preserve-env=HUMAN sh -c 'chown --recursive $HUMAN:$HUMAN /opt/android-sdk-linux/'

cat <<-EOF >> $HOME/.profile

export ANDROID_AVD_HOME=\$HOME/.avd
export ANDROID_SDK_HOME=\$HOME/.android
export ANDROID_PREFS_ROOT=\$HOME/.android
export ANDROID_HOME=/opt/android-sdk-linux
export ANDROID_SDK_ROOT=/opt/android-sdk-linux

EOF
