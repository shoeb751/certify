FROM alpine:3.13.5 AS build

# Install tools required for project
# Run `docker build --no-cache .` to update dependencies
RUN apk update && apk add --no-cache gcc make unzip libc-dev && \
        mkdir -p /opt/build && cd /opt/build && \
        wget https://github.com/juce/sockproc/archive/master.zip && \
        unzip master.zip && rm master.zip && cd sockproc-master && \
        make

FROM openresty/openresty:alpine
COPY --from=build /opt/build/sockproc-master/sockproc /bin/
ADD ./misc/start.sh /bin/start.sh
RUN apk update && apk add --no-cache openssl coreutils file curl && chmod 775 /bin/start.sh
CMD ["/bin/start.sh"]