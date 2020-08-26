#!/bin/bash

export PLUGIN_CMD=${PLUGIN_CMD//,/ && }

for ALIAS in ${PLUGIN_IMAGE_ALIASES//,/ }; do
    ORIGINAL=$(echo $ALIAS | cut -d '=' -f 1)
    NEW=$(echo $ALIAS | cut -d '=' -f 2)

    echo "🐑 Pulling image $ORIGINAL and retagging as $NEW"
    docker pull $ORIGINAL 2>&1 | sed 's/^/   /g'
    docker tag $ORIGINAL $NEW 2>&1 | sed 's/^/   /g'
done