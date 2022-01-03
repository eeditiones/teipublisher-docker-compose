# Docker Compose Configuration

This repository contains a docker compose configuration useful to run TEI Publisher and associated services. For security reasons, it is recommended to not expose TEI Publisher and eXist-db directly, but instead protect them behind a proxy. The [docker-compose](docker-compose.yml) file therefore sets up an nginx reverse proxy.

The following services are configured by the [docker-compose](docker-compose.yml):

* publisher: main TEI Publisher application
* ner: TEI Publisher named entity recognition service
* frontend: nginx reverse proxy which forwards requests to TEI Publisher
* certbot: letsencrypt certbot required to register an SSL certificate

The publisher and ner services will be built from the corresponding github repositories using the current master branch.

# Default Configuration

By default, the compose configuration will launch the proxy on port 80 of the local host, serving only http, not https. This configuration is intended for testing, not for deployment on a public facing server.

To start, simply call

```sh
docker compose up -d
```

Afterwards you should be able to access TEI Publisher using http://localhost.

# Deployment on a Public Server

If you would like to deploy the configuration to a public server, you must first acquire an SSL certificate to enable users to securly connect via https. The compose configuration is already prepared to make this as easy as possible.

1. Copy the nginx configuration file [conf/example.com.tmpl](conf/example.com.tmpl) to e.g. `conf/my.domain.com.conf`, where `my.domain.com` would correspond to the domain name of the webserver you are configuring the service for
2. Open the copied file in an editor and replace all occurrences of `example.com` with your domain name
3. Also change the name of the **upstream** entry to a unique name (otherwise it will collide with the default config):
   ```
    upstream docker-publisher.example.com {
        server publisher:8080 fail_timeout=0;
    }
    ```

    Change the two references to the `docker-publisher` upstream server below accordingly, e.g.:

    ```
    proxy_pass http://docker-publisher.example.com/exist/apps/tei-publisher$request_uri;
    ```

4. Run the following command to request an SSL certificate for your domain, again replacing the final `example.com` with your domain name:
   ```sh
   docker compose run --rm  certbot certonly --webroot --webroot-path /var/www/certbot/ -d example.com
   ```
5. In the nginx configuration file, uncomment the two lines starting with `# ssl_certificate` by removing the leading `#`:
   ```
   ssl_certificate /etc/nginx/ssl/live/publisher.jinntec.com/fullchain.pem;
   ssl_certificate_key /etc/nginx/ssl/live/publisher.jinntec.com/privkey.pem;
   ```
6. Stop and restart the services:
   ```sh
   docker restart
   ```