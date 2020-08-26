#!/bin/bash

set -euo pipefail # Abort on error, strict variable interpolation, fail if piped command fails

run_hook_scripts() {
  for HOOK_SCRIPT in /dind-drone-plugin/hooks/$1/*; do
    if [[ -x $HOOK_SCRIPT ]]; then
      echo "📄 Running $1 hook script $HOOK_SCRIPT"
      /bin/bash $HOOK_SCRIPT || exit 1
    fi
  done
}

if [[ "${PLUGIN_CMD:-}" == "" ]]; then
  echo "One or more cmd arguments must be provided"
  exit 1
fi
# If multiple cmd lines have been provided, chain them into something which we can execute with sh
# Note that Drone provides these lines in comma separated form without escaping, which means commas in commands are known to break
export PLUGIN_CMD=${PLUGIN_CMD//,/ && }

# Wrap command scriptlet in an invocation of sh
export PLUGIN_CMD="sh -c '${PLUGIN_CMD}'"

run_hook_scripts pre_daemon_start

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

run_hook_scripts post_daemon_start

echo "   Available images before build:"
docker image ls 2>&1 | sed 's/^/   /g'

cd ${CI_WORKSPACE}

# Ensure that secrets (passed through as env vars) are available. Iterate and purposefully omit newlines.
for k in $(compgen -e); do
  echo $k=${!k} >> ${PWD}/outer_env_vars.env
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

run_hook_scripts pre_run

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

run_hook_scripts post_run

rm outer_env_vars.env

exit $CMD_EXIT_CODE