#!/bin/sh
# set -e # if not existsの代替を検討するまで、エラーは無視
apt update && apt install -y curl
export PGUSER=$POSTGRES_USER
psql -c "CREATE DATABASE pechka;"

curl -s https://raw.githubusercontent.com/k-wa-wa/pechka/refs/heads/master/file-server/db/000_init.sql | psql -d pechka
curl -s https://raw.githubusercontent.com/k-wa-wa/pechka/refs/heads/master/file-server/db/001_create_playlists_table.sql | psql -d pechka
