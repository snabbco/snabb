FROM alpine:3.4

RUN apk update && apk add luajit strace

COPY . .

ENTRYPOINT ["luajit"]
