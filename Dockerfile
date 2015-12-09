FROM alpine

RUN apk update && apk add luajit

COPY . .

ENTRYPOINT ["luajit"]
