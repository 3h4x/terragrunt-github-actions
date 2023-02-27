FROM alpine:3

RUN ["/bin/sh", "-c", "apk add --update --no-cache bash ca-certificates curl git jq"]

COPY ["src", "/src/"]
RUN adduser runner -g runner -D

USER runner

ENTRYPOINT ["/src/main.sh"]
