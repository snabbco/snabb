FROM alpine:3.4
RUN apk update && apk add luajit luajit-dev strace && mkdir -p /usr/share/lua/5.1
COPY . /usr/share/lua/5.1/
ENTRYPOINT ["luajit"]
