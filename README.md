# Proton Swap history database

## Installation

(replace `secretsecret` with a strong password)

```
curl -s https://packagecloud.io/install/repositories/timescale/timescaledb/script.deb.sh | bash

apt install -y timescaledb-2-postgresql-14
timescaledb-tune -yes -memory 20GB

sed -e "s/.*listen_addresses.*/listen_addresses = \'\*\'/" -i /etc/postgresql/14/main/postgresql.conf

cat >>/etc/postgresql/14/main/pg_hba.conf <<'EOT'
host all all 0.0.0.0/0 scram-sha-256
EOT

systemctl restart postgresql

apt install -y cpanminus libjson-xs-perl libjson-perl libdbi-perl libdbd-pg-perl libwww-perl make gcc
cpanm --notest Net::WebSocket::Server

cd /var/local
wget https://github.com/EOSChronicleProject/eos-chronicle/releases/download/v2.2/eosio-chronicle-2.2-Clang-11.0.1-ubuntu22.04-x86_64.deb
apt install ./eosio-chronicle-2.2-Clang-11.0.1-ubuntu22.04-x86_64.deb
cp /usr/local/share/chronicle_receiver\@.service /etc/systemd/system/
systemctl daemon-reload

git clone https://github.com/Antelope-Memento/antelope_memento.git /opt/antelope_memento
cd /opt/antelope_memento
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload


su postgres -c psql

CREATE ROLE proton_swap_rw WITH LOGIN PASSWORD 'secretsecret';
CREATE ROLE proton_swap_ro WITH LOGIN PASSWORD 'proton_swap_ro';
ALTER ROLE proton_swap_ro NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;

CREATE DATABASE proton_swap;
GRANT ALL PRIVILEGES ON DATABASE proton_swap TO proton_swap_rw;

GRANT CONNECT ON DATABASE proton_swap TO proton_swap_ro;

\c proton_swap

CREATE EXTENSION IF NOT EXISTS timescaledb;
exit

cat >>~/.pgpass <<'EOT'
localhost:*:*:proton_swap_rw:secretsecret
EOT

export PGHOST=localhost
psql --username=proton_swap_rw --dbname=proton_swap </opt/antelope_memento/sql/postgres/memento_timescale.sql

git clone https://github.com/cc32d9/proton_swap_db.git /opt/proton_swap_db
psql --username=proton_swap_rw --dbname=proton_swap </opt/proton_swap_db/proton_swap_tables.sql
psql --username=proton_swap_rw --dbname=proton_swap -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO proton_swap_ro"

echo 'DBWRITER_OPTS="--id=1 --port=8005 --dsn=dbi:Pg:dbname=proton_swap;host=localhost --dbuser=proton_swap_rw --dbpw=secretsecret --plugin=/opt/proton_swap_db/proton_swap_dbwriter.pl --notraces"' >/etc/default/memento_proton_swap

systemctl enable memento_dbwriter@proton_swap
systemctl start memento_dbwriter@proton_swap

# in this example, Proton state history is available at 10.0.3.1:8085

mkdir -p /srv/memento_proton_swap/chronicle-config
cat >/srv/memento_proton_swap/chronicle-config/config.ini <<'EOT'
host = 10.0.3.1
port = 8085
mode = scan
skip-block-events = true
plugin = exp_ws_plugin
exp-ws-host = 127.0.0.1
exp-ws-port = 8005
exp-ws-bin-header = true
skip-table-deltas = true
skip-account-info = true
enable-receiver-filter = true
include-receiver = proton.swaps
EOT

cd /srv/memento_proton_swap
rm -rf chronicle-data
curl https://snapshots.eosamsterdam.net/public/chronicle-2.x/chronicle-data_proton_43656600.tar.gz | tar xzSvf -

systemctl enable chronicle_receiver@memento_proton_swap
systemctl start chronicle_receiver@memento_proton_swap
```

## Public access

Public access is provided by [EOS Amsterdam block producer](https://eosamsterdam.net/).

```
Postgres host: memento.eu.eosamsterdam.net
Port: 5501
Username: proton_swap_ro
Password: proton_swap_ro
Database: proton_swap
```


## Acknowledgments

Copyright 2022 cc32d9@gmail.com
