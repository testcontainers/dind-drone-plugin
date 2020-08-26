#!/bin/bash

pull_if_absent() {
  if [[ $(docker images ${1} | wc -l) < 2 ]]; then
    echo "🚚 Pulling image: ${1}"
    docker pull ${1} 2>&1 | sed 's/^/   /g'
  fi
}

if [[ "${PLUGIN_PREFETCH_IMAGES:-}" != "" ]]; then
  echo "🚚 Prefetching images in background:"
  for IMG in $(echo ${PLUGIN_PREFETCH_IMAGES} | sed "s/,/ /g"); do
    echo "   $IMG"
    pull_if_absent "$IMG" > /dev/null &
  done
fi

pull_if_absent ${PLUGIN_BUILD_IMAGE}
