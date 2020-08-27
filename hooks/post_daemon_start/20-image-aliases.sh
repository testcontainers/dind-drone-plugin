#!/bin/bash

echo $PLUGIN_IMAGE_ALIASES | jq -r 'to_entries[] | [.key, .value] | @tsv' | while read ORIGINAL NEW; do
    echo "🐑 Pulling image $ORIGINAL and retagging as $NEW"
    docker pull $ORIGINAL 2>&1 | sed 's/^/   /g'
    docker tag $ORIGINAL $NEW 2>&1 | sed 's/^/   /g'
done