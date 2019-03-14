#!/bin/bash

set -euo pipefail # Abort on error, strict variable interpolation, fail if piped command fails
IMAGE_CACHE_DIR=${CI_WORKSPACE}/.dind

if [[ "${PLUGIN_CMD:-}" == "" ]]; then
  echo "One or more cmd arguments must be provided"
  exit 1
fi
# If multiple cmd lines have been provided, chain them into something which we can execute with sh
# Note that Drone provides these lines in comma separated form without escaping, which means commas in commands are known to break
export PLUGIN_CMD=${PLUGIN_CMD//,/ && }

# Wrap command scriptlet in an invocation of sh
export PLUGIN_CMD="sh -c '${PLUGIN_CMD}'"

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

set +e
if [[ -d $IMAGE_CACHE_DIR ]]; then
  echo "💾 Importing docker images from cache ($IMAGE_CACHE_DIR)"
  for IMAGE in $(ls $IMAGE_CACHE_DIR); do
    cat $IMAGE_CACHE_DIR/$IMAGE | gunzip | docker image load
  done
fi
set -e


if [[ "${PLUGIN_DOCKER_LOGIN_COMMAND:-}" != "" ]]; then
  echo "🛠  Executing Docker login command"
  sh -c "${PLUGIN_DOCKER_LOGIN_COMMAND}" 2>&1 | sed "s/^/    /g"
fi

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
set +e
eval $CMD
CMD_EXIT_CODE=$?
echo; echo
echo "🏁 Exit code: $CMD_EXIT_CODE"

mkdir -p $IMAGE_CACHE_DIR
docker image prune -f
echo "💾 Exporting docker images to cache ($IMAGE_CACHE_DIR)"
for IMAGE in $(docker image ls -q); do
  if [[ ! -f $IMAGE_CACHE_DIR/$IMAGE.tar.gz ]]; then
    docker image save $IMAGE | gzip > $IMAGE_CACHE_DIR/$IMAGE.tar.gz
  fi
done

exit $CMD_EXIT_CODE