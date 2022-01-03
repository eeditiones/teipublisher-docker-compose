# Docker Compose Configuration

This repository contains a docker compose configuration useful to run TEI Publisher and associated services. For security reasons, it is recommended to not expose TEI Publisher and eXist-db directly, but instead run protect behind a proxy. The [docker-compose](docker-compose.yml) file therefore sets up an nginx reverse proxy.

The following services are configured by the [docker-compose](docker-compose.yml):

* publisher: main TEI Publisher application
* ner: TEI Publisher named entity recognition service
* frontend: nginx reverse proxy which forwards requests to TEI Publisher
* certbot: letsencrypt certbot required to register an SSL certificate

The publisher and ner services will be built from the corresponding github repositories using the current master branch.