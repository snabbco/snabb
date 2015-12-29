FROM alpine:3.3

RUN apk update && apk add luajit strace

COPY . .

ENTRYPOINT ["luajit"]
