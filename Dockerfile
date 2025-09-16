FROM python:3.8-alpine

LABEL "com.github.actions.name"="S3 Sync"
LABEL "com.github.actions.description"="Sync a directory to an AWS S3 repository"
LABEL "com.github.actions.icon"="refresh-cw"
LABEL "com.github.actions.color"="green"

LABEL version="0.5.1"
LABEL repository="https://github.com/jakejarvis/s3-sync-action"
LABEL homepage="https://jarv.is/"
LABEL maintainer="Jake Jarvis <jake@jarv.is>"

# https://github.com/aws/aws-cli/blob/master/CHANGELOG.rst
ENV AWSCLI_VERSION='1.18.14'

RUN apk update \
    && apk add --no-cache git \
    && pip install --quiet --no-cache-dir awscli==${AWSCLI_VERSION} \
    && rm -rf /var/cache/apk/*

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
