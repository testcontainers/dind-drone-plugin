FROM docker:27.2.0-dind

RUN apk add --no-cache bash jq

#### Script that starts docker in docker
ADD command.sh /dind-drone-plugin/command.sh
RUN chmod +x /dind-drone-plugin/command.sh

#### Hook scripts
ADD hooks /dind-drone-plugin/hooks

ENTRYPOINT ["/dind-drone-plugin/command.sh"]
