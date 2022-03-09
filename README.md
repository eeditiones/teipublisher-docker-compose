# Docker Compose Configuration

This repository contains a docker compose configuration useful to run TEI Publisher and associated services. Docker compose allows us to orchestrate and coordinate the various services, while keeping each service in its own, isolated environment. Setting up a server via docker compose is fast as everything comes preconfigured and you don't need to install all the dependencies (like Java, eXist-db, Python etc.) by hand. On the downside, it certainly introduces some overhead and will never be as fast as a server, which is properly maintained. For smaller, low-traffic projects docker is a viable and cheap alternative though.

For security reasons, it is recommended to not expose TEI Publisher and eXist-db directly, but instead protect them behind a proxy. The [docker-compose](docker-compose.yml) file therefore sets up an nginx reverse proxy.

The following services are configured by the [docker-compose](docker-compose.yml):

* publisher: main TEI Publisher application
* ner: TEI Publisher named entity recognition service
* frontend: nginx reverse proxy which forwards requests to TEI Publisher
* certbot: letsencrypt certbot required to register an SSL certificate

The publisher and ner services will be built from the corresponding github repositories using the current master branch. You thus only need to clone this repository to either your local machine or a server you are installing. Everything else is handled automatically by docker compose.

# Default Configuration

By default, the compose configuration will launch the proxy on port 80 of the local host, serving only http, not https. This configuration is intended for testing, not for deployment on a public facing server.

To build all the services, call

```sh
docker compose build --build-arg ADMIN_PASS=my_pass
```

where `my_pass` sets the password for the eXist admin user (recommended). You can remove the `--build-arg` parameter entirely to keep an empty password.

To start, simply call

```sh
docker compose up -d
```

Afterwards you should be able to access TEI Publisher using http://localhost. Additionally eXide can be accessed via http://localhost/apps/eXide (on a production system you want to disable that).

# Deployment on a Public Server

If you would like to deploy the configuration to a public server, you must first acquire an SSL certificate to enable users to securly connect via https. The compose configuration is already prepared to make this as easy as possible.

1. Clone this repository to a folder on the server
1. Copy the nginx configuration file [conf/example.com.tmpl](conf/example.com.tmpl) to e.g. `conf/my.domain.com.conf`, where `my.domain.com` would correspond to the domain name of the webserver you are configuring the service for
2. Open the copied file in an editor and replace all occurrences of `example.com` with your domain name. *Important*: this also applies to the commented out SSL section, which you will enable later below.
3. Change the name of the **upstream** entry to a unique name (otherwise it will collide with the default config):
   ```
    upstream docker-publisher.example.com {
        server publisher:8080 fail_timeout=0;
    }
    ```

    Change the two references to the `docker-publisher` upstream server below accordingly (including the commented out SSL section):

    ```
    proxy_pass http://docker-publisher.example.com/exist/apps/tei-publisher$request_uri;
    ...
    proxy_pass http://docker-publisher.example.com/exist$request_uri;
    ```
4. Start the services to acquire SSL certificates in the next step using `docker compose up -d`
5. Run the following command to request an SSL certificate for your domain, again replacing the final `example.com` with your domain name:
   ```sh
   docker compose run --rm  certbot certonly --webroot --webroot-path /var/www/certbot/ -d example.com
   ```

   This will ask you for an email address, verify your server and store certificate files into `certbot/conf/`.

6. In the nginx configuration file, uncomment the SSL section by removing the leading `#`
7. Stop and restart the services:
   ```sh
   docker compose restart
   ```