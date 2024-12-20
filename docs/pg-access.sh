# set up port forward
kubectl port-forward nuage-postgres-0 6432:5432

export PGPASSWORD=$(kubectl get secret postgres.nuage-postgres.credentials.postgresql.acid.zalan.do -o 'jsonpath={.data.password}' | base64 -d)
export PGSSLMODE=require
psql -U postgres -h localhost -p 6432
