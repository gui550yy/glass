FROM kerberos/debian-opencv-ffmpeg:1.0.0 AS builder
MAINTAINER Kerberos.io

ENV GOROOT=/usr/local/go
ENV GOPATH=/go
ENV PATH=$GOPATH/bin:$GOROOT/bin:$PATH
ENV GOSUMDB=off

##############################################################################
# Copy all the relevant source code in the Docker image, so we can build this.

RUN mkdir -p /go/src/github.com/kerberos-io/glass
COPY api /go/src/github.com/kerberos-io/glass/api
COPY frontend /go/src/github.com/kerberos-io/glass/frontend

########################
# Download NPM and Yarns

RUN apt-get install curl && curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
    apt update && apt install yarn -y

###########
# Build Frontend

RUN cd /go/src/github.com/kerberos-io/glass/frontend && \
    npm install && yarn build
    # this will move the /build directory to ../api/www

##################
# Build API

RUN cd /go/src/github.com/kerberos-io/glass/api && \
   go mod download && \
   go build main.go && \
	 mkdir -p /glass && \
	 mv main /glass && \
	 mv www /glass && \
	 rm -rf /go/src/gitlab.com/

 ####################################
 # Let's create a /dist folder containing just the files necessary for runtime.
 # Later, it will be copied as the / (root) of the output image.

 WORKDIR /dist
 RUN cp -r /glass ./

 ####################################
 # This will collect dependent libraries so they're later copied to the final image

 RUN ldd /glass/main | tr -s '[:blank:]' '\n' | grep '^/' | \
     xargs -I % sh -c 'mkdir -p $(dirname ./%); cp % ./%;'
 RUN mkdir -p lib64 && cp /lib64/ld-linux-x86-64.so.2 lib64/
 RUN ldd /glass/main

 FROM alpine:latest

 #################################
 # Copy files from previous images

 COPY --chown=0:0 --from=builder /dist /
 COPY --chown=0:0 --from=builder /usr/local/go/lib/time/zoneinfo.zip /zoneinfo.zip

 ENV ZONEINFO=/zoneinfo.zip

 RUN apk update && apk add ca-certificates && \
     apk add --no-cache tzdata && rm -rf /var/cache/apk/*

 ####################################
 # ADD supervisor and STARTUP script
 # NOTE: actually this is not needed, as we could simply run a single binary.

 RUN apk add supervisor && mkdir -p /var/log/supervisor/
 ADD ./scripts/supervisor.conf /etc/supervisord.conf
 ADD ./scripts/run.sh /run.sh
 RUN chmod 755 /run.sh && chmod +x /run.sh

 ######################################
 # By default the app runs on port 8080

 EXPOSE 8080

 CMD ["sh", "/run.sh"]
