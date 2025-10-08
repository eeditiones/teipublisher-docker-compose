ARG EXIST_VERSION=6.2.0
ARG TP_MAJOR=v9
ARG BUILD=local

FROM ghcr.io/eeditiones/builder:latest AS builder

ARG APP_NAME=tei-publisher-app
ARG APP_REPO=https://github.com/eeditiones/tei-publisher-app.git
ARG APP_TAG_OR_BRANCH=master

# Access token for private repo to be passed to docker as secret

WORKDIR /tmp

# Build the main app configured in the docker-compose.yml
# replace with name of your edition repository and choose branch to build
RUN  git clone ${APP_REPO} \
    # replace my-edition with name of your app
    && cd ${APP_NAME} \
    && echo Checking out ${APP_TAG_OR_BRANCH} \
    && git checkout ${APP_TAG_OR_BRANCH} \
    && ant

FROM ghcr.io/jinntec/base:${EXIST_VERSION}

ARG APP_NAME=tei-publisher-app
ARG USR=nonroot:nonroot
USER ${USR}

COPY --from=builder --chown=${USR} /tmp/${APP_NAME}/build/*.xar /exist/autodeploy/

ARG HTTP_PORT=8080
ARG HTTPS_PORT=8443

ARG NER_ENDPOINT=http://localhost:8001
ARG CONTEXT_PATH=auto
ARG PROXY_CACHING=false

ENV JDK_JAVA_OPTIONS="\
    -Dteipublisher.ner-endpoint=${NER_ENDPOINT} \
    -Dteipublisher.context-path=${CONTEXT_PATH} \
    -Dteipublisher.proxy-caching=${PROXY_CACHING}"

# pre-populate the database by launching it once
RUN [ "java", "org.exist.start.Main", "client", "--no-gui",  "-l" ]

EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
