# Adds one app, built from a git repository, on top of the jinks image.
# Used by docker-compose.build.yml; the default setup runs the jinks image directly.
ARG BASE_IMAGE=ghcr.io/eeditiones/jinks:latest

FROM ghcr.io/eeditiones/builder:latest AS builder

ARG APP_NAME=tei-publisher-app
ARG APP_REPO=https://github.com/eeditiones/tei-publisher-app.git
ARG APP_TAG_OR_BRANCH=master

WORKDIR /tmp

RUN  git clone ${APP_REPO} ${APP_NAME} \
    && cd ${APP_NAME} \
    && echo Checking out ${APP_TAG_OR_BRANCH} \
    && git checkout ${APP_TAG_OR_BRANCH} \
    && ant

FROM ${BASE_IMAGE}

ARG APP_NAME=tei-publisher-app

COPY --from=builder /tmp/${APP_NAME}/build/*.xar /exist/autodeploy/

# pre-populate the database by launching it once
RUN [ "java", "org.exist.start.Main", "client", "--no-gui",  "-l", "-u", "admin", "-P", "" ]
