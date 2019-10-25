FROM docker:19.03.0-dind

RUN apk add --no-cache bash

#### Script that starts docker in docker
ADD command.sh /command.sh
RUN chmod +x /command.sh

ENTRYPOINT ["/command.sh"]
