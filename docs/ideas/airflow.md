# apache airflow

```sh
helm repo add apache-airflow https://airflow.apache.org
helm repo update

export NAMESPACE=test-wf
kubectl create namespace $NAMESPACE

export RELEASE_NAME=test-wf
helm install $RELEASE_NAME apache-airflow/airflow \
  --namespace $NAMESPACE \
  --set-string "env[0].name=AIRFLOW__CORE__LOAD_EXAMPLES" \
  --set-string "env[0].value=True"
```
