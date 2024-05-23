#!/bin/bash

cat <<EOF >>/etc/docker/daemon.json
{
    "insecure-registries" : ["domain"]
}
EOF
