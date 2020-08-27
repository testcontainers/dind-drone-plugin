#!/bin/bash

if [[ "${PLUGIN_DOCKER_LOGIN_COMMAND:-}" != "" ]]; then
  echo "🛠  Executing Docker login command"
  sh -c "${PLUGIN_DOCKER_LOGIN_COMMAND}" 2>&1 | sed "s/^/    /g"
fi