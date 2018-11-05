FROM docker:18.09.0-dind

#### Script that starts docker in docker
ADD command.sh /command.sh
RUN chmod +x /command.sh

ENTRYPOINT ["/command.sh"]
