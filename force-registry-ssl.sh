#!/bin/bash

cat <<EOF >>/etc/docker/daemon.json
{
    "insecure-registries" : ["reg-v1.ut.ac.id"]
}
EOF
