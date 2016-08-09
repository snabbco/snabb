FROM alpine:3.4

RUN apk update && apk add luajit luajit-dev strace && mkdir -p /usr/share/lua/5.1

COPY syscall.lua /usr/share/lua/5.1/
COPY syscall /usr/share/lua/5.1/syscall/

ENTRYPOINT ["luajit"]
