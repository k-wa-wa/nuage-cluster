#!/bin/sh
# set -e # if not existsの代替を検討するまで、エラーは無視

psql -c "CREATE DATABASE pechka;"

curl -s https://raw.githubusercontent.com/k-wa-wa/pechka/refs/heads/master/file-server/db/init.sql | psql -d pechka
