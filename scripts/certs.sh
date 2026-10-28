#!/usr/bin/env bash
# Generates one root CA and one intermediate CA per cluster, signed by that
# root, the way tools/certs/Makefile.selfsigned.mk of Istio does it (same key
# sizes, extensions and file names). Output in certs/ (gitignored):
#   certs/root-cert.pem, certs/root-key.pem
#   certs/<cluster>/{ca-cert.pem, ca-key.pem, root-cert.pem, cert-chain.pem}
# Usage: certs.sh <root-name> <cluster>...   (root-name is a directory name)
# The lab keeps the root key on disk only for the length of a run; in
# production the root lives offline or in a KMS/HSM and never on a laptop.
set -euo pipefail

ROOT_NAME="$1"; shift
DIR="$(cd "$(dirname "$0")/.." && pwd)/certs/${ROOT_NAME}"
mkdir -p "${DIR}"
cd "${DIR}"

if [ ! -f root-key.pem ]; then
  cat > root-ca.conf <<EOF
[ req ]
encrypt_key = no
prompt = no
utf8 = yes
default_md = sha256
default_bits = 4096
req_extensions = req_ext
x509_extensions = req_ext
distinguished_name = req_dn
[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign
[ req_dn ]
O = Istio
CN = Root CA ${ROOT_NAME}
EOF
  openssl genrsa -out root-key.pem 4096 2>/dev/null
  openssl req -sha256 -new -key root-key.pem -config root-ca.conf -out root-cert.csr
  openssl x509 -req -sha256 -days 3650 -signkey root-key.pem \
    -extensions req_ext -extfile root-ca.conf -in root-cert.csr -out root-cert.pem 2>/dev/null
fi

for cluster in "$@"; do
  mkdir -p "${cluster}"
  cat > "${cluster}/intermediate.conf" <<EOF
[ req ]
encrypt_key = no
prompt = no
utf8 = yes
default_md = sha256
default_bits = 4096
req_extensions = req_ext
x509_extensions = req_ext
distinguished_name = req_dn
[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign
subjectAltName=@san
[ san ]
DNS.1 = istiod.istio-system.svc
[ req_dn ]
O = Istio
CN = Intermediate CA
L = ${cluster}
EOF
  openssl genrsa -out "${cluster}/ca-key.pem" 4096 2>/dev/null
  openssl req -sha256 -new -config "${cluster}/intermediate.conf" -key "${cluster}/ca-key.pem" -out "${cluster}/cluster-ca.csr"
  openssl x509 -req -sha256 -days 3650 -CA root-cert.pem -CAkey root-key.pem -CAcreateserial \
    -extensions req_ext -extfile "${cluster}/intermediate.conf" \
    -in "${cluster}/cluster-ca.csr" -out "${cluster}/ca-cert.pem" 2>/dev/null
  cp root-cert.pem "${cluster}/root-cert.pem"
  cat "${cluster}/ca-cert.pem" root-cert.pem > "${cluster}/cert-chain.pem"
done
