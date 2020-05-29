#!/bin/bash

set -euo pipefail # Abort on error, strict variable interpolation, fail if piped command fails

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
/usr/local/bin/dockerd-entrypoint.sh dockerd \
  --data-root /drone/docker \
  -s ${PLUGIN_STORAGE_DRIVER:-overlay2} \
  --log-level error \
  -H tcp://0.0.0.0:2375 \
  -H unix:///var/run/docker.sock &

for i in $(seq 1 30); do
  echo "⏳ Pinging docker daemon ($i/30)"
  docker ps &> /dev/null && break || true
  sleep 1
done

docker ps &> /dev/null || exit 1
echo "✅ Docker-in-Docker is running..."

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
  touch ${PWD}/outer_env_vars.env
  case "$k" in
      # avoid overwriting container's variables
      
# Note that the env vars to blacklist may be found using
#   `docker run -it --entrypoint env quay.io/testcontainers/dind-drone-plugin`
   DIND_COMMIT|DOCKER_CHANNEL|DOCKER_TLS_CERTDIR|DOCKER_VERSION|HOME|HOSTNAME|PATH|PWD|SHLVL)
      ;;
    *)
      echo $k=${!k} >> ${PWD}/outer_env_vars.env
      ;;
  esac
done

# Determine IP address at which dockerd and spawned containers can be reached
DOCKER_IP=$(ip route | awk '/docker0/ { print $7 }')
echo "DOCKER_HOST=tcp://${DOCKER_IP}:2375" >> ${PWD}/outer_env_vars.env
echo "ℹ️  Docker daemon will be available in the build container:"
echo "     at /var/run/docker.sock"
echo "     at tcp://${DOCKER_IP}:2375 (no TLS)"
echo "ℹ️  DOCKER_HOST will be set to tcp://${DOCKER_IP}:2375"
echo "ℹ️  Containers spawned by the build container will be accessible at ${DOCKER_IP} (do not hardcode this value)"

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

rm outer_env_vars.env

exit $CMD_EXIT_CODE
