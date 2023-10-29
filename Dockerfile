# START STAGE 1
FROM openjdk:8-jdk-slim as builder

USER root

ENV ANT_VERSION 1.10.13
ENV ANT_HOME /etc/ant-${ANT_VERSION}

WORKDIR /tmp

RUN apt-get update && apt-get install -y \
    git \
    curl

RUN curl -L -o apache-ant-${ANT_VERSION}-bin.tar.gz http://www.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mkdir ant-${ANT_VERSION} \
    && tar -zxvf apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mv apache-ant-${ANT_VERSION} ${ANT_HOME} \
    && rm apache-ant-${ANT_VERSION}-bin.tar.gz \
    && rm -rf ant-${ANT_VERSION} \
    && rm -rf ${ANT_HOME}/manual \
    && unset ANT_VERSION

ENV PATH ${PATH}:${ANT_HOME}/bin

# workaround: install OS provided nodejs and npm packages
RUN apt-get update && apt-get install -y nodejs npm

#RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
#     && apt-get install -y nodejs \
#     && curl -L https://www.npmjs.com/install.sh | sh

FROM builder as tei

ARG TEMPLATING_VERSION=1.1.0
ARG PUBLISHER_LIB_VERSION=3.0.0
ARG ROUTER_VERSION=1.8.0

# replace with name of your edition repository and choose branch to build
ARG MY_EDITION_VERSION=master

# add key
RUN  mkdir -p ~/.ssh && ssh-keyscan -t rsa gitlab.existsolutions.com >> ~/.ssh/known_hosts
#RUN  mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# Replace git URL below to point to your git repository 
RUN  git clone https://github.com/eeditiones/tei-publisher-app.git \
    # replace my-edition with name of your app
    && cd tei-publisher-app \
    && echo Checking out ${MY_EDITION_VERSION} \
    && git checkout ${MY_EDITION_VERSION} \
    && ant

RUN curl -L -o /tmp/roaster-${ROUTER_VERSION}.xar https://exist-db.org/exist/apps/public-repo/public/roaster-${ROUTER_VERSION}.xar
RUN curl -L -o /tmp/tei-publisher-lib-${PUBLISHER_LIB_VERSION}.xar https://exist-db.org/exist/apps/public-repo/public/tei-publisher-lib-${PUBLISHER_LIB_VERSION}.xar
RUN curl -L -o /tmp/templating-${TEMPLATING_VERSION}.xar https://exist-db.org/exist/apps/public-repo/public/templating-${TEMPLATING_VERSION}.xar

FROM duncdrum/existdb:6.2.0-debug-j8

COPY --from=tei /tmp/tei-publisher-app/build/*.xar /exist/autodeploy/
COPY --from=tei /tmp/*.xar /exist/autodeploy/

WORKDIR /exist

ARG ADMIN_PASS=none

ARG HTTP_PORT=8080
ARG HTTPS_PORT=8443

ARG NER_ENDPOINT=http://localhost:8001
ARG CONTEXT_PATH=auto
ARG PROXY_CACHING=false

ENV JAVA_TOOL_OPTIONS \
  -Dfile.encoding=UTF8 \
  -Dsun.jnu.encoding=UTF-8 \
  -Djava.awt.headless=true \
  -Dorg.exist.db-connection.cacheSize=${CACHE_MEM:-256}M \
  -Dorg.exist.db-connection.pool.max=${MAX_BROKER:-20} \
  -Dlog4j.configurationFile=/exist/etc/log4j2.xml \
  -Dexist.home=/exist \
  -Dexist.configurationFile=/exist/etc/conf.xml \
  -Djetty.home=/exist \
  -Dexist.jetty.config=/exist/etc/jetty/standard.enabled-jetty-configs \
  -Dteipublisher.ner-endpoint=${NER_ENDPOINT} \
  -Dteipublisher.context-path=${CONTEXT_PATH} \
  -Dteipublisher.proxy-caching=${PROXY_CACHING} \
  -XX:+UseG1GC \
  -XX:+UseStringDeduplication \
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=${JVM_MAX_RAM_PERCENTAGE:-75.0} \
  -XX:+ExitOnOutOfMemoryError

# pre-populate the database by launching it once
#RUN bin/client.sh -l --no-gui --xpath "system:get-version()"
#RUN if [ "${ADMIN_PASS}" != "none" ]; then bin/client.sh -l --no-gui --xpath "sm:passwd('admin', '${ADMIN_PASS}')"; fi
RUN [ "java", "org.exist.start.Main", "client", "--no-gui",  "-l", "-u", "admin", "-P", "" ]

EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
