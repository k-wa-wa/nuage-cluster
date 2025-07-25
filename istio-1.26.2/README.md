
tls証明書の作成

```bash
openssl genrsa -out tls.key 2048
openssl req -new -key tls.key -out tls.csr -config openssl.cnf
openssl x509 -req -in tls.csr -signkey tls.key \
  -out tls.crt -days 365 \
  -extensions req_ext -extfile openssl.cnf
```