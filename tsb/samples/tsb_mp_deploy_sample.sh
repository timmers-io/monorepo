export REGISTRY="mstsbacrx9pslvvlqec0jpg3.azurecr.io"
export FOLDER="."
export BASE_FQDN="example.com"
export TSB_FQDN_PREFIX="tsb"

function create_cert() {
  local readonly name=$1
  local readonly folder=$2
  local readonly conf=$3
  local readonly ca_cert=$4
  local readonly ca_key=$5
  local readonly ca_chain=$6

  openssl genrsa \
    -out "${FOLDER}/${name}.key" \
    4096

  # generate tsb_int_ca certs
  openssl req \
    -new \
    -config "${conf}" \
    -key "${FOLDER}/${name}.key" \
    -out "${FOLDER}/${name}.csr"

  # sign tsb_int_ca certificate with root CA
  openssl x509 \
    -req \
    -days 90 \
    -CA "${ca_cert}" \
    -CAkey "${ca_key}" \
    -CAcreateserial \
    -extensions req_ext \
    -extfile "${conf}" \
    -in "${FOLDER}/${name}.csr" \
    -out "${FOLDER}/${name}.crt"

}

cat >"${FOLDER}/ca.cnf" <<EOF
# all the fields in this CNF are just example, Client should follow its own PKI practice to configue it properly
[ req ]
encrypt_key        = no
utf8               = yes
default_bits       = 4096
default_md         = sha256
prompt             = no
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = req_ext

[ req_distinguished_name ]
countryName         = US
stateOrProvinceName = CA
organizationName    = Example
commonName          = SelfSignedRootCA

[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints     = critical, CA:true
keyUsage             = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign
EOF

openssl genrsa \
  -out "${FOLDER}/ca.key" \
  4096

openssl req \
  -new \
  -key "${FOLDER}/ca.key" \
  -config "${FOLDER}/ca.cnf" \
  -out "${FOLDER}/ca.csr"

openssl x509 \
  -req \
  -days 90 \
  -signkey "${FOLDER}/ca.key" \
  -extensions req_ext \
  -extfile "${FOLDER}/ca.cnf" \
  -in "${FOLDER}/ca.csr" \
  -out "${FOLDER}/ca.crt"

cat >"${FOLDER}/tsb_envoy.cnf" <<EOF
# all the fields in this CNF are just example, Client should follow its own PKI practice to configue it properly
[ req ]
encrypt_key        = no
utf8               = yes
default_bits       = 4096
default_md         = sha256
prompt             = no
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = req_ext

[ req_distinguished_name ]
countryName         = US
stateOrProvinceName = CA
organizationName    = Example
commonName          = Example TSB Envoy GUI

[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints     = critical, CA:false
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = serverAuth, clientAuth
subjectAltName       = @alt_names

[ alt_names ]
IP.1 = 10.64.8.208
DNS.1 = ${TSB_FQDN_PREFIX}.${BASE_FQDN}
EOF


create_cert tsb_mp \
  "${FOLDER}" \
  "${FOLDER}/tsb_envoy.cnf" \
  "${FOLDER}/ca.crt" \
  "${FOLDER}/ca.key" 
cat >"${FOLDER}/xcp_mpc.cnf" <<EOF
# fields for 'req_distinguished_name' in this CNF are just example
[ req ]
encrypt_key        = no
utf8               = yes
default_bits       = 4096
default_md         = sha256
prompt             = no
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = req_ext

[ req_distinguished_name ]
countryName         = US
stateOrProvinceName = CA
organizationName    = Example
commonName          = XCP MPC

# you will have to use 'extendedKeyUsage = serverAuth, clientAuth' because it will be checked by the TSB.
[ req_ext ]
basicConstraints = critical, CA:false
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName   = @alt_names

# you will have to use the following DNS name and URI because it will be checked by the TSB
[ alt_names ]
DNS.1 = xcp.tetrate.io
URI.1 = spiffe://xcp.tetrate.io/mpc
EOF

create_cert xcp_mpc \
  "${FOLDER}" \
  "${FOLDER}/xcp_mpc.cnf" \
  "${FOLDER}/ca.crt" \
  "${FOLDER}/ca.key" 


cat >"${FOLDER}/xcp_central.cnf" <<EOF
# fields for 'req_distinguished_name' in this CNF are just example
[ req ]
encrypt_key        = no
utf8               = yes
default_bits       = 4096
default_md         = sha256
prompt             = no
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = req_ext

[ req_distinguished_name ]
countryName         = US
stateOrProvinceName = CA
organizationName    = Example
commonName          = XCP Central

# you will have to use 'extendedKeyUsage = serverAuth, clientAuth' because it will be checked by the TSB.
[ req_ext ]
basicConstraints = critical, CA:false
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName   = @alt_names

# you will have to use the following DNS name and URI because it will be checked by the TSB
[ alt_names ]
DNS.1 = xcp.tetrate.io
URI.1 = spiffe://xcp.tetrate.io/central
EOF

create_cert xcp_central \
  "${FOLDER}" \
  "${FOLDER}/xcp_central.cnf" \
  "${FOLDER}/ca.crt" \
  "${FOLDER}/ca.key"  
  
kubectl create secret generic xcp-central-cert -n tsb \
  --from-file=tls.crt="${FOLDER}/xcp_central.crt" \
  --from-file=tls.key="${FOLDER}/xcp_central.key" \
  --from-file=ca.crt="${FOLDER}/ca.crt"

kubectl create secret generic mpc-certs -n tsb \
  --from-file=tls.crt="${FOLDER}/xcp_mpc.crt" \
  --from-file=tls.key="${FOLDER}/xcp_mpc.key" \
  --from-file=ca.crt="${FOLDER}/ca.crt"
  

curl -o tctl140 https://binaries.dl.tetrate.io/public/raw/versions/darwin-amd64-1.4.0/tct
chmod a+x tctl140

./tctl140 install manifest management-plane-operator \
  --registry $REGISTRY > ${FOLDER}/managementplaneoperator.yaml

kubectl apply -f ${FOLDER}/managementplaneoperator.yaml

kubectl get pod -n tsb

./tctl140 install manifest management-plane-secrets \
    --allow-defaults \
    --tsb-admin-password "Tetrate123" \
    --tsb-server-certificate "$(cat tsb_mp.crt)" \
    --tsb-server-key "$(cat tsb_mp.key)" > ${FOLDER}/managementplane-secrets.yaml

kubectl apply -f ${FOLDER}/managementplane-secrets.yaml

cat >"${FOLDER}/managementplane.yaml" <<EOF
apiVersion: install.tetrate.io/v1alpha1
kind: ManagementPlane
metadata:
  name: managementplane
  namespace: tsb
spec:
  hub: $REGISTRY
  organization: tetrate
  components:
    frontEnvoy:
      kubeSpec:
        service:
          annotations:
            service.beta.kubernetes.io/azure-load-balancer-internal: "true"
          type: LoadBalancer
    xcp:
      centralAuthModes:
        jwt: true
        mutualTls: true
      kubeSpec:
        overlays:
        - apiVersion: install.xcp.tetrate.io/v1alpha1
          kind: CentralXcp
          name: central-xcp
          patches:
          - path: spec.components.centralServer.kubeSpec.service.annotations
            value:
              service.beta.kubernetes.io/azure-load-balancer-internal: "true"
          - path: spec.components.centralServer.kubeSpec.overlays
            value:
            - apiVersion: v1
              kind: Service
              name: xcp-central
              patches:
              - path: spec.type
                value: LoadBalancer
EOF

kubectl create job -n tsb teamsync-bootstrap --from=cronjob/teamsync

./tctl140 config clusters set default --bridge-address $(kubectl get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}'):8443
./tctl140 config profiles set-current default
./tctl140 login --org tetrate --username admin --password Tetrate123 --tenant tetrate
