#!/bin/bash

sed -i "s/1024/3072 -b 1024 -d 1024 -i 1024/g" /usr/lib/systemd/system/haveged.service
systemctl daemon-reload && systemctl restart haveged && sudo systemctl restart sysstat

# Point us at the development environment.
tee --append /etc/hosts <<-EOF > /dev/null
192.168.221.246 api.centos.local
192.168.221.242 vpn.centos.local
192.168.221.242 242.vpn.centos.local
192.168.221.243 243.vpn.centos.local
192.168.221.244 244.vpn.centos.local
192.168.221.245 245.vpn.centos.local
EOF

dnf -q -y module enable go-toolset
dnf -q -y install jq git gcc curl make expect golang coreutils gnutls-utils python3-jinja2 python3-netaddr python3-yaml python3-six

[ -d $HOME/daemon-0.7 ] && rm --force --recursive $HOME/daemon-0.7
cd $HOME && curl --silent --show-error --location --output $HOME/daemon-0.7.tar.gz http://libslack.org/daemon/download/daemon-0.7.tar.gz
printf "f66af2ece784c16dcb5219de1f4fa3ae5787bb3374e44bd4b1d3e275e8ff272c  daemon-0.7.tar.gz" | sha256sum -c || exit 1
tar xzf daemon-0.7.tar.gz && cd $HOME/daemon-0.7 && ./configure && make install && cd $HOME

export PATH=$PATH:$HOME/go/bin

[ -d $HOME/vpnweb ] && rm --force --recursive $HOME/vpnweb
git clone https://0xacab.org/leap/vpnweb.git/ $HOME/vpnweb && cd $HOME/vpnweb

[ -d /etc/vpnweb/ ] && rm --force --recursive /etc/vpnweb/
mkdir --parents /etc/vpnweb/public/
mkdir --parents /etc/vpnweb/public/1/
mkdir --parents /etc/vpnweb/public/3/

cat <<-EOF > /etc/default/vpnweb
VPNWEB_AUTH=anon
VPNWEB_PORT=443
VPNWEB_ADDRESS=192.168.221.246
VPNWEB_REDIRECT=https://lavabit.com/
VPNWEB_AUTH_SECRET="`mkpasswd -l 32 -d 6 -C 6 -s 0 -d 4`"
VPNWEB_API_PATH=/etc/vpnweb/public/
VPNWEB_PROVIDER_CA=/etc/vpnweb/ca-cert.pem
VPNWEB_TLSCRT=/etc/vpnweb/tls-cert.pem
VPNWEB_TLSKEY=/etc/vpnweb/tls-key.pem
VPNWEB_CACRT=/etc/vpnweb/ca-cert.pem
VPNWEB_CAKEY=/etc/vpnweb/ca-key.pem
EOF

cat <<-EOF > /etc/vpnweb/ca.cfg
organization = "Lavabit LLC"
unit = "Lavabit Developer Proxy"
state = "Texas"
country = US
email = "support@centos.local"
cn = "centos.local"
dc = "centos.local"
serial = 001
activation_date = "2021-01-01 10:00:00"
expiration_date = "2031-12-31 23:59:59"
dns_name = "centos.local"
ca
signing_key
encryption_key
cert_signing_key
EOF

cat <<-EOF > /etc/vpnweb/tls-cert.cfg
organization = "Lavabit LLC"
unit = "Lavabit Developer Proxy"
state = "Texas"
country = US
email = "support@centos.local"
cn = "api.centos.local"
dc = "centos.local"
serial = 002
activation_date = "2021-01-01 12:00:00"
expiration_date = "2031-12-31 12:00:00"
dns_name = "api.centos.local"
signing_key
encryption_key
tls_www_server
EOF

# CA
certtool --sec-param=ultra --generate-privkey --outfile /etc/vpnweb/ca-key.pem
certtool --sec-param=ultra --generate-self-signed --load-privkey /etc/vpnweb/ca-key.pem --outfile /etc/vpnweb/ca-cert.pem --template /etc/vpnweb/ca.cfg

# TLS
certtool --sec-param=ultra --generate-privkey --outfile /etc/vpnweb/tls-key.pem --template /etc/vpnweb/tls-cert.cfg
certtool --sec-param=ultra --generate-request --load-privkey /etc/vpnweb/tls-key.pem --outfile /etc/vpnweb/tls-request.pem --template /etc/vpnweb/tls-cert.cfg
certtool --sec-param=ultra --generate-certificate --load-request=/etc/vpnweb/tls-request.pem --load-privkey /etc/vpnweb/tls-key.pem --outfile /etc/vpnweb/tls-cert.pem \
  --load-ca-certificate /etc/vpnweb/ca-cert.pem --load-ca-privkey /etc/vpnweb/ca-key.pem --template /etc/vpnweb/tls-cert.cfg

rm --force /etc/vpnweb/ca.cfg
rm --force /etc/vpnweb/tls-cert.cfg
rm --force /etc/vpnweb/tls-request.pem

export FINGERPRINT="`certtool --certificate-info --infile /etc/vpnweb/ca-cert.pem | grep 'sha256:' | head -1 | tr -d '[:space:]' | awk -F':' '{print $2}'`"

cat <<-EOF > /etc/vpnweb/provider.yaml
auth: anon

openvpn:
    - auth: SHA256
    - cipher: AES-256-GCM
    - keepalive: "10 30"
    - tls-cipher: TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
    - tun-ipv6: true
    - dev: tun
    - sndbuf: 0
    - rcvbuf: 0
    - nobind: true
    - persist-key: true
    - key-direction: 1

locations:
    - Dallas:
        - name: Dallas
        - country_code: US
        - hemisphere: N
        - timezone: -6

gateways:
    - 242.vpn.centos.local:
        - host: 242.vpn.centos.local
        - ip_address: 192.168.221.242
        - location: Dallas
        - transports:
            - [ "openvpn", "tcp", "443"]
    - 243.vpn.centos.local:
        - host: 243.vpn.centos.local
        - ip_address: 192.168.221.243
        - location: Dallas
        - transports:
            - [ "openvpn", "tcp", "443"]
    - 244.vpn.centos.local:
        - host: 244.vpn.centos.local
        - ip_address: 192.168.221.244
        - location: Dallas
        - transports:
            - [ "openvpn", "tcp", "443"]
    - 245.vpn.centos.local:
        - host: 245.vpn.centos.local
        - ip_address: 192.168.221.245
        - location: Dallas
        - transports:
            - [ "openvpn", "tcp", "443"]

provider:
    - name: "CentOS Test Proxy"
    - description: "CentOS Test Proxy"
    - domain: centos.local
    - api_uri: api.centos.local
    - fingerprint: "SHA256: $FINGERPRINT"
EOF

cat <<-EOF > /etc/vpnweb/public/1/service.json
{
  "name": "anonymous",
  "description": "anonymous access to the VPN",
  "eip_rate_limit": false
}
EOF

cat <<-EOF > /etc/vpnweb/public/1/configs.json
{
  "services": {
    "eip": "/1/configs/eip-service.json"
  }
}
EOF

cat <<-EOF > /etc/vpnweb/public/3/service.json
{
  "name": "anonymous",
  "description": "anonymous access to the VPN",
  "eip_rate_limit": false
}
EOF

cat <<-EOF > /etc/vpnweb/public/3/configs.json
{
  "services": {
    "eip": "/3/configs/eip-service.json"
  }
}
EOF

cat <<-EOF > $HOME/vpnweb/scripts/templates/eip-service.1.json.jinja
{
  "serial": 1,
  "version": 1,
  "locations": { {% for loc in locations %}
      "{{loc}}": {
          "name": "{{ locations[loc]['name'] }}",
          "country_code": "{{ locations[loc]['country_code'] }}",
          "hemisphere": "{{ locations[loc]['hemisphere'] }}",
          "timezone": "{{ locations[loc]['timezone'] }}"
      }{{ "," if not loop.last }}{% endfor %}
  },
  "gateways": [ {% for gw in gateways %}
      {
          "host": "{{ gateways[gw]["host"] }}",
          "ip_address": "{{ gateways[gw]["ip_address"] }}",
          "location": "{{ gateways[gw]["location"] }}",
          "capabilities": {
            "adblock": false,
            "filter_dns": false,
            "limited": false,
            "ports": [
              "443"
            ],
            "protocols": [
              "tcp"
            ],
            "transport": [
              "openvpn"
            ],
            "user_ips": false
        }
    }{{ "," if not loop.last }}{% endfor %}
  ],
  "openvpn_configuration": {{ openvpn|tojson(indent=8) }}
}
EOF

cat <<-EOF > $HOME/vpnweb/scripts/templates/eip-service.3.json.jinja
{
    "auth": "{{ auth }}",
    "serial": 1,
    "version": 3,
    "locations": { {% for loc in locations %}
        "{{loc}}": {
            "name": "{{ locations[loc]['name'] }}",
            "country_code": "{{ locations[loc]['country_code'] }}",
            "hemisphere": "{{ locations[loc]['hemisphere'] }}",
            "timezone": "{{ locations[loc]['timezone'] }}"
        }{{ "," if not loop.last }}{% endfor %}
    },
    "gateways": [ {% for gw in gateways %}
        {
            "host": "{{ gateways[gw]["host"] }}",
            "ip_address": "{{ gateways[gw]["ip_address"] }}",
            "location": "{{ gateways[gw]["location"] }}",
            "capabilities": {
                "adblock": false,
                "filter_dns": false,
                "limited": false,
                "transport": [ {% for tr, proto, port, options in gateways[gw]["transports"] %}
                    {"type": "{{ tr }}",
                     "protocols": ["{{ proto }}"],{% if options %}
                     "options": {{ options | tojson }},{% endif %}
                     "ports": ["{{ port }}"]
                    }{{ "," if not loop.last }}{% endfor %}
                ]
            }
        }{{ "," if not loop.last }}{% endfor %}
    ],
    "openvpn_configuration": {{ openvpn|tojson(indent=8) }}
}
EOF

patch -p1 <<-EOF
diff --git a/scripts/templates/provider.json.jinja b/scripts/templates/provider.json.jinja
index f54a3c0..43bcf5e 100644
--- a/scripts/templates/provider.json.jinja
+++ b/scripts/templates/provider.json.jinja
@@ -5 +5 @@
-  "ca_cert_uri": "https://{{ provider.domain }}/ca.crt",
+  "ca_cert_uri": "https://{{ provider.api_uri }}/ca.crt",
EOF

patch -p1 <<-EOF
diff --git a/pkg/config/config.go b/pkg/config/config.go
index b2d3e6d..bbb4a5e 100644
--- a/pkg/config/config.go
+++ b/pkg/config/config.go
@@ -35,0 +36,2 @@ type Opts struct {
+       Address        string
+       Redirect       string
@@ -94,0 +97,2 @@ func initializeFlags(opts *Opts) {
+       flag.StringVar(&opts.Address, "address", "", "Listen for connections on a specific IP address or leave empty to listen on all IP address (default: empty)")
+       flag.StringVar(&opts.Redirect, "redirect", "", "Redirect any unhandled/unecpected URLs to this address")
@@ -106,0 +111,2 @@ func initializeFlags(opts *Opts) {
+       FallbackToEnv(&opts.Address, "VPNWEB_ADDRESS", "")
+       FallbackToEnv(&opts.Redirect, "VPNWEB_REDIRECT", "")
EOF

patch -p1 <<-EOF
diff --git a/pkg/web/certs.go b/pkg/web/certs.go
index 203c9d9..8931d46 100644
--- a/pkg/web/certs.go
+++ b/pkg/web/certs.go
@@ -28 +27,0 @@ import (
-	mrand "math/rand"
@@ -32,13 +31,3 @@ import (
-const keySize = 2048
-const expiryDays = 28
-const certPrefix = "UNLIMITED"
-
-var letterRunes = []rune("abcdefghijklmnopqrstuvwxyz")
-
-func randStringRunes(n int) string {
-	b := make([]rune, n)
-	for i := range b {
-		b[i] = letterRunes[mrand.Intn(len(letterRunes))]
-	}
-	return string(b)
-}
+const keySize = 4096
+const expiryDays = 120
+const certPrefix = "BAZINGA"
@@ -67 +56,5 @@ func (ci *caInfo) CertWriter(out io.Writer) {
-	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
+	serialMin := new(big.Int).SetInt64(1000)
+	serialNumber := new(big.Int).SetInt64(0)
+	for serialNumber.Cmp(serialMin) < 0 {
+		serialNumber, err = rand.Int(rand.Reader, serialNumberLimit)
+	}
@@ -72 +64,0 @@ func (ci *caInfo) CertWriter(out io.Writer) {
-	_ = randStringRunes(25)
@@ -78 +69,0 @@ func (ci *caInfo) CertWriter(out io.Writer) {
-			//CommonName: certPrefix + randStringRunes(25),
EOF

cat <<-EOF > $HOME/vpnweb/main.go
package main

import (
  "log"
  "net/http"
  "path/filepath"

  "0xacab.org/leap/vpnweb/pkg/auth"
  "0xacab.org/leap/vpnweb/pkg/config"
  "0xacab.org/leap/vpnweb/pkg/web"
)

func main() {
  opts := config.NewOpts()
  ch := web.NewCertHandler(opts.CaCrt, opts.CaKey)
  authenticator := auth.GetAuthenticator(opts, false)

  srv := http.NewServeMux()

  /* protected routes */
  srv.Handle("/cert", web.RestrictedMiddleware(authenticator.NeedsCredentials, ch.CertResponder, opts))
  srv.Handle("/1/cert", web.RestrictedMiddleware(authenticator.NeedsCredentials, ch.CertResponder, opts))
  srv.Handle("/3/cert", web.RestrictedMiddleware(authenticator.NeedsCredentials, ch.CertResponder, opts))

  /* files */
  web.HttpFileHandler(srv, "/ca.crt", opts.ProviderCaPath)
  web.HttpFileHandler(srv, "/provider.json", filepath.Join(opts.ApiPath, "provider.json"))

  web.HttpFileHandler(srv, "/1/ca.crt", opts.ProviderCaPath)
  web.HttpFileHandler(srv, "/1/configs.json", filepath.Join(opts.ApiPath, "1", "configs.json"))
  web.HttpFileHandler(srv, "/1/service.json", filepath.Join(opts.ApiPath, "1", "service.json"))
  web.HttpFileHandler(srv, "/1/config/eip-service.json", filepath.Join(opts.ApiPath, "1", "eip-service.json"))

  web.HttpFileHandler(srv, "/3/ca.crt", opts.ProviderCaPath)
  web.HttpFileHandler(srv, "/3/configs.json", filepath.Join(opts.ApiPath, "3", "configs.json"))
  web.HttpFileHandler(srv, "/3/service.json", filepath.Join(opts.ApiPath, "3", "service.json"))
  web.HttpFileHandler(srv, "/3/config/eip-service.json", filepath.Join(opts.ApiPath, "3", "eip-service.json"))

  /* catchall redirect */
  if opts.Redirect != "" {
    srv.Handle("/", http.RedirectHandler(opts.Redirect, http.StatusMovedPermanently))
  }

  /* address setup */
  pstr := ":" + opts.Port
  if opts.Address != "" {
    pstr = opts.Address + ":" + opts.Port
  }

  /* api server */
  if opts.Tls == true {
    log.Fatal(http.ListenAndServeTLS(pstr, opts.TlsCrt, opts.TlsKey, srv))
  } else {
    log.Fatal(http.ListenAndServe(pstr, srv))
  }
}
EOF

go clean -i -r -cache -modcache && go build -a

# $HOME/vpnweb/scripts/gen-shapeshifter-state.py /etc/vpnweb/shapeshifter-state/
# python3 $HOME/vpnweb/scripts/simplevpn.py --file=eip --config=/etc/vpnweb/provider.yaml --template=$HOME/vpnweb/scripts/templates/eip-service.1.json.jinja --obfs4_state=/etc/vpnweb/shapeshifter-state/ | jq -M '.' > /etc/vpnweb/public/1/eip-service.json || echo "ERROR: see /etc/vpnweb/public/1/eip-service.json for output"
# python3 $HOME/vpnweb/scripts/simplevpn.py --file=eip --config=/etc/vpnweb/provider.yaml --template=$HOME/vpnweb/scripts/templates/eip-service.3.json.jinja --obfs4_state=/etc/vpnweb/shapeshifter-state/ | jq -M '.' > /etc/vpnweb/public/3/eip-service.json || echo "ERROR: see /etc/vpnweb/public/3/eip-service.json for output"
python3 $HOME/vpnweb/scripts/simplevpn.py --file=eip --config=/etc/vpnweb/provider.yaml --template=$HOME/vpnweb/scripts/templates/eip-service.1.json.jinja | jq -M '.' > /etc/vpnweb/public/1/eip-service.json || echo "ERROR: see /etc/vpnweb/public/1/eip-service.json for output"
python3 $HOME/vpnweb/scripts/simplevpn.py --file=eip --config=/etc/vpnweb/provider.yaml --template=$HOME/vpnweb/scripts/templates/eip-service.3.json.jinja | jq -M '.' > /etc/vpnweb/public/3/eip-service.json || echo "ERROR: see /etc/vpnweb/public/3/eip-service.json for output"
python3 $HOME/vpnweb/scripts/simplevpn.py --file=provider --config=/etc/vpnweb/provider.yaml --template=$HOME/vpnweb/scripts/templates/provider.json.jinja | jq -M '.' > /etc/vpnweb/public/provider.json || echo "ERROR: see /etc/vpnweb/provider.json for output"

# Kill any existing vpnweb processes and install the new binary.
[ -d /run/vpnweb/ ] && [ -f /run/vpnweb/vpnweb.pid ] && /usr/bin/pkill --pidfile /run/vpnweb/vpnweb.pid

# Create the user, if necessary.
id vpnweb &> /dev/null || adduser --system --shell /sbin/nologin --home-dir /etc/vpnweb/ --no-create-home vpnweb

# Ensure the vpnweb user can access the vpnweb config path.
chown -R vpnweb:vpnweb /etc/vpnweb/

# Setup the pidfile directory.
cat <<-EOF > /usr/lib/tmpfiles.d/vpnweb.conf
D /run/vpnweb 0700 vpnweb vpnweb
EOF

chcon system_u:object_r:lib_t:s0 /usr/lib/tmpfiles.d/vpnweb.conf
[ ! -d /run/vpnweb/ ] && systemd-tmpfiles --create /usr/lib/tmpfiles.d/vpnweb.conf

# Install the binary and the systemd unit file.
install -m 755 $HOME/vpnweb/vpnweb /usr/local/bin/ && setcap 'cap_net_bind_service=+ep' /usr/local/bin/vpnweb

cat <<-EOF > /usr/lib/systemd/system/vpnweb.service
[Unit]
Description=vpnweb
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=vpnweb
Group=vpnweb
EnvironmentFile=/etc/default/vpnweb
ExecStart=/usr/local/bin/daemon --inherit --pidfile=/run/vpnweb/vpnweb.pid -- /usr/local/bin/vpnweb -tls=true
ExecStop=bash -c '/usr/bin/test -f /run/vpnweb/vpnweb.pid && /usr/bin/pkill --pidfile /run/vpnweb/vpnweb.pid || echo noop > /dev/null'
ExecReload=bash -c '/usr/bin/test -f /run/vpnweb/vpnweb.pid && /usr/bin/pkill --signal HUP --pidfile /run/vpnweb/vpnweb.pid || echo noop > /dev/null'
LimitNOFILE=65535

# Hardening
ProtectHome=yes
PrivateTmp=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

chcon system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/vpnweb.service

systemctl daemon-reload
systemctl enable vpnweb.service && systemctl start vpnweb.service

echo "VPN web service installed."
echo "Starting unit tests."
sleep 10

curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/ca.crt || { echo "https://api.centos.local/ca.crt failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/provider.json || { echo "https://api.centos.local/provider.json failed ..." ; exit 1 ; }

curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/1/cert || { echo "https://api.centos.local/1/cert failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/1/ca.crt || { echo "https://api.centos.local/1/ca.crt failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/1/configs.json || { echo "https://api.centos.local/1/configs.json failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/1/service.json || { echo "https://api.centos.local/1/service.json failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/1/config/eip-service.json || { echo "https://api.centos.local/1/config/eip-service.json failed ..." ; exit 1 ; }

curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/3/cert || { echo "https://api.centos.local/3/cert failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/3/ca.crt || { echo "https://api.centos.local/3/ca.crt failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/3/configs.json || { echo "https://api.centos.local/3/configs.json failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/3/service.json || { echo "https://api.centos.local/3/service.json failed ..." ; exit 1 ; }
curl --fail --silent --show-error --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/3/config/eip-service.json || { echo "https://api.centos.local/3/config/eip-service.json failed ..." ; exit 1 ; }

curl --fail --silent --show-error --insecure --location --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/ || { echo "https://api.centos.local/ redirection failed ..." ; exit 1 ; }
curl --fail --silent --show-error --insecure --location --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem https://api.centos.local/$RANDOM || { echo "https://api.centos.local/RANDOM redirection failed ..." ; exit 1 ; }

for i in {1..100}; do
  URL="`cat /dev/urandom | tr -dc '[:alnum:]\#\\\/\.\-\_' | fold -w 32 | head -n 1`"
  curl --fail --silent --show-error --globoff --insecure --location --retry 10 --retry-delay 10 --max-time 300 --connect-timeout 300 --output /dev/null --cacert /etc/vpnweb/ca-cert.pem "https://api.centos.local/${URL}" || { echo "https://api.centos.local/${URL} redirection failed" ; exit 1 ; }
done

echo "Unit tests completed."

# Cleanup.
rm --force --recursive $HOME/go/ $HOME/.cache/ $HOME/vpnweb/ $HOME/daemon-0.7/ $HOME/daemon-0.7.tar.gz
dnf -q -y module disable go-toolset && dnf -q -y remove jq git gcc make golang expect gnutls-utils python3-jinja2 python3-netaddr python3-yaml patch
