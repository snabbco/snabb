FROM alpine:3.7 AS build
RUN apk add --no-cache libgcc alpine-sdk gcc libpcap-dev linux-headers findutils
COPY . /snabb
RUN cd /snabb && make clean && make -j && cd src && make -j

FROM alpine:3.7
RUN apk add --no-cache libgcc
COPY --from=build /snabb/src/snabb /usr/local/bin/

VOLUME /u
WORKDIR /u

ENTRYPOINT ["/usr/local/bin/snabb"]
