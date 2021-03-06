FROM alpine:3.13.5 AS build

# Install tools required for project
# Run `docker build --no-cache .` to update dependencies
RUN apk update && apk add --no-cache gcc make unzip libc-dev && \
        mkdir -p /opt/build && cd /opt/build && \
        wget https://github.com/juce/sockproc/archive/master.zip && \
        unzip master.zip && rm master.zip && cd sockproc-master && \
        make
RUN mkdir -p /opt/nsq && cd /opt/nsq && \
    wget https://s3.amazonaws.com/bitly-downloads/nsq/nsq-1.2.0.linux-amd64.go1.12.9.tar.gz && \
    tar -xf nsq-1.2.0.linux-amd64.go1.12.9.tar.gz && \
    ls -R .

FROM openresty/openresty:alpine
COPY --from=build /opt/build/sockproc-master/sockproc /bin/
COPY --from=build /opt/nsq/nsq-1.2.0.linux-amd64.go1.12.9/bin/nsqd /bin/
COPY ./lua /etc/nginx/lua
COPY ./nginx/html /var/www/html
COPY ./nginx/conf.d /etc/nginx/conf.d
ADD ./misc/start.sh /bin/start.sh
RUN apk update && apk add --no-cache openssl coreutils file curl && chmod 775 /bin/start.sh
CMD ["/bin/start.sh"]