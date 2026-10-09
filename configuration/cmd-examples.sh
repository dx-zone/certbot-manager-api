# cmd-examples.sh

# Server side
sudo ./cert-manager-api \                                                                                     ✘ [04:32:34PM]
  -listen :8443 \
  -tls-cert /opt/certbot/datastore/certbot-data/letsencrypt/live/x.mydatacenter.io/fullchain.pem \
  -tls-key /opt/certbot/datastore/certbot-data/letsencrypt/live/x.mydatacenter.io/privkey.pem \
  -client-ca /opt/certbot/secrets/rpmrepo-secrets/pki_mtls_material/ca.crt \
  -allowed-cns ./clients.txt \
  -ip-list ./ips.txt \
  -ip-policy allow \
  -cert-csv ./certificates.csv



# Client side
sudo curl -v \                                                                                                ✔ [04:24:36PM]
  --cacert /opt/certbot/secrets/rpmrepo-secrets/pki_mtls_material/ca.crt \
  --cert /opt/certbot/secrets/rpmrepo-secrets/pki_mtls_material/client-identity.crt \
  --key /opt/certbot/secrets/rpmrepo-secrets/pki_mtls_material/client-identity.key \
  https://x.mydatacenter.io:8443