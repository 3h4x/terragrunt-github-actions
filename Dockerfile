FROM alpine:3

RUN apk add --update --no-cache bash ca-certificates curl git jq coreutils openssh-client

COPY ["src", "/src/"]
RUN adduser runner -g runner -D

USER runner

ENTRYPOINT ["/src/main.sh"]
