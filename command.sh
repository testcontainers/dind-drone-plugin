#!/bin/bash

set -euo pipefail # Abort on error, strict variable interpolation, fail if piped command fails

echo "📦 Starting dind-drone-plugin"

echo "🐳 Starting docker-in-docker daemon"
/usr/local/bin/dockerd-entrypoint.sh dockerd --data-root /drone/docker -s ${PLUGIN_STORAGE_DRIVER:-vfs} --log-level error &

for i in $(seq 1 30); do
  echo "⏳ Pinging docker daemon ($i/30)"
  docker ps &> /dev/null && break || true
  sleep 1
done

docker ps &> /dev/null || exit 1
echo "✅ Docker-in-Docker is running..."

if [[ "${PLUGIN_PREFETCH_IMAGES:-}" != "" ]]; then
  echo "🚚 Prefetching images in background:"
  for IMG in $(echo ${PLUGIN_PREFETCH_IMAGES} | sed "s/,/ /g"); do
    echo "   $IMG"
    $(docker pull "$IMG" > /dev/null) &
  done
fi

cd ${CI_WORKSPACE}

echo "🚚 Pulling build image: ${PLUGIN_BUILD_IMAGE}"
docker pull ${PLUGIN_BUILD_IMAGE} 2>&1 | sed 's/^/   /g'

# Ensure that secrets (passed through as env vars) are available. Iterate and purposefully omit newlines.
for k in $(compgen -e); do
  echo $k=${!k} >> ${PWD}/outer_env_vars.env
done

echo -e "\n\n"
MSG="🚀 About to run command: ${PLUGIN_CMD} on image ${PLUGIN_BUILD_IMAGE} inside Docker-in-Docker"
echo -e $MSG
echo -n " $MSG" | sed 's/./=/g'
echo -e "\n\n"

CMD="docker run -v /var/run/docker.sock:/var/run/docker.sock \
                -v ${PWD}:${PWD} -w ${PWD} --rm \
                --env-file ${PWD}/outer_env_vars.env \
                ${EXTRA_DOCKER_OPTIONS:-} \
                ${PLUGIN_BUILD_IMAGE} ${PLUGIN_CMD}"

echo -n "$ "
echo $CMD
echo -e "\n\n"
exec $CMD