#### DevOps Univ Terbuka 2021

## Postgresql 13 - Prometheus - Postgres Exporter - Node Exporter -> Grafana (Tested On Centos 7)
### Setup Grafana dashboard untuk postgresql-13

```sh

yum update

yum install wget -y

yum install nano -y

yum install dnf -y

systemctl stop firewalld

systemctl disable firewalld

cat <<EOF | sudo tee /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

yum install grafana -y

#prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.29.1/prometheus-2.29.1.linux-amd64.tar.gz
 
tar -xzf prometheus-2.29.1.linux-amd64.tar.gz
 
mkdir -p /root/prometheus-files
 
mv prometheus-2.29.1.linux-amd64 prometheus-files
 
cp /root/prometheus-files/prometheus /usr/bin/
 
cp /root/prometheus-files/promtool /usr/bin/

#node exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.2.2/node_exporter-1.2.2.linux-amd64.tar.gz
 
tar -xzf node_exporter-1.2.2.linux-amd64.tar.gz
 
cp node_exporter-1.2.2.linux-amd64/node_exporter /usr/bin/
 
node_exporter --version

node_exporter &amp;

#tambahkan ini di config yml prometheus
static_configs:
 
- targets: ["ipservernya:9090"]
- targets: ["ipservernya:9100"]
- targets: ["ipservernya:9187"]


#Test prometheus

/usr/bin/prometheus --config.file /root/prometheus-files/prometheus.yml --storage.tsdb.path /root/prometheus-files/promdb --web.console.templates=/root/prometheus-files/consoles --web.console.libraries=/root/prometheus-files/console_libraries
http://ipservernya:9090/targets


#Postgres exporter
yum install epel-release -y
 
yum install golang -y
 
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.10.0/postgres_exporter-0.10.0.linux-amd64.tar.gz
 
tar -xzf postgres_exporter-0.10.0.linux-amd64.tar.gz
 
cp postgres_exporter-0.10.0.linux-amd64/postgres_exporter /usr/bin
 
postgres_exporter --version

#untuk test connection postgres
psql -d "postgresql://USERNYA:PASSWORDNYA@IPNYA:5432/postgres?sslmode=disable"

#Export env -> contoh
export DATA_SOURCE_NAME="postgresql://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable"

#Buat Service Prometheus (yang web console bisa dimatikan (untuk log itu))
cat <<EOF | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
 
[Service]
User=root
Group=root
Type=simple
ExecStart=/usr/bin/prometheus \
--config.file /root/prometheus-files/prometheus.yml \
--storage.tsdb.path /root/prometheus-files/promdb \
--web.console.templates=/root/prometheus-files/consoles \ 
--web.console.libraries=/root/prometheus-files/console_libraries
[Install]
WantedBy=multi-user.target
EOF

#Buat Service node exporter
cat <<EOF | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus exporter for Postgresql
Wants=network-online.target
After=network-online.target
[Service]
User=postgres
Group=postgres
ExecStart=/usr/bin/node_exporter
Restart=always
[Install]
WantedBy=multi-user.target
EOF

#Buat Service Postgres Exporter
cat <<EOF | sudo tee /etc/systemd/system/postgres_exporter.service
[Unit]
Description=Prometheus exporter for Postgresql
Wants=network-online.target
After=network-online.target
[Service]
User=postgres
Group=postgres
WorkingDirectory=/opt/postgres_exporter
EnvironmentFile=/opt/postgres_exporter/postgres_exporter.env
ExecStart=/usr/bin/postgres_exporter
Restart=always
[Install]
WantedBy=multi-user.target
EOF

#Start - Enable service node exporter - prometheus - postgres exporter - grafana

systemctl daemon-reload

systemctl enable prometheus

systemctl start prometheus

systemctl enable node_exporter

systemctl start node_exporter

systemctl enable postgres_exporter

systemctl start postgres_exporter

systemctl start grafana-server

systemctl enable grafana-server

#ID Import Grafana
Import linux (nodenya) metrics -> dashboard URL ID : 1860
Import PostgreSQL Metrics -> dashboard URL ID : 9628

```
```sh
#prometheus service example
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.external-url=http://34.89.26.156:9090 \
    --storage.tsdb.retention.time=1y #data retention akan dihapus otomatis
[Install]
WantedBy=multi-user.target
```
