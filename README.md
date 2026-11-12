# Docker Compose Configuration

This repository contains a docker compose configuration useful to run TEI Publisher and associated services.Docker compose allows us to orchestrate and coordinate the various services, while keeping each service in its own, isolated environment. Setting up a server via docker compose is fast as everything comes preconfigured and you don't need to install all the dependencies (like Java, eXist-db, Python etc.) by hand. On the downside, it certainly introduces some overhead and may never be as fast as a server, which is properly maintained. For smaller, low-traffic projects docker is a viable and cheap alternative though.

For security reasons, it is recommended to not expose TEI Publisher and eXist-db directly, but instead protect them behind a proxy. The [docker-compose](docker-compose.yml) configuration therefore sets up an nginx reverse proxy.

The following services are configured by the [docker-compose](docker-compose.yml):

* publisher: eXist-db with [jinks](https://github.com/eeditiones/jinks), the TEI Publisher app generator (image `ghcr.io/eeditiones/jinks:latest`)
* exist-init: one-shot helper which provides a static busybox to the publisher container so it can set the admin password on first start
* ner: TEI Publisher named entity recognition service
* frontend: nginx reverse proxy which forwards requests to TEI Publisher
* certbot: letsencrypt certbot required to register an SSL certificate
* cantaloupe: a IIIF server for images

In this repository we provide two ways to set up and configure a server:

1. **simple setup**: ideal for local testing or projects which need to build and expose a single application. Installing a server involves a few manual steps like copying files and running a command.
2. **ansible**: fully-automated setup without manual steps. Also suited for projects serving multiple applications, optionally under different domain names. More information can be found [below](#ansible-setup).

# Simple setup

## Default configuration (local testing only)

Clone this repository to either your local machine or a server you are installing. By default it runs the latest jinks release (`ghcr.io/eeditiones/jinks:latest`) without any additional apps. The root of the server is mapped to jinks; apps you generate with jinks remain reachable below `/exist/apps/`. The named entity recognition and cantaloupe iiif services are pulled as ready-made images. If you do not need or want the named entity recognition or cantaloupe service, comment out the corresponding sections in `docker-compose.yml`, including the `depends_on:` for ner and/or cantaloupe found in the file. TEI Publisher will still work.

By default, the compose configuration will launch the proxy on port 80 of the local host, serving only http, not https. This configuration is intended for testing, not for deployment on a public facing server. To start the services on localhost using the default configuration, run:

```sh
docker compose up -d
```

Afterwards you should be able to access jinks using http://localhost. The cantaloupe IIIF service will be mapped to the path `/iiif`, so for testing try: http://localhost/iiif/2/test.tif/full/full/0/default.jpg. See [below](#using-iiif) for more information.

To stop the services again, call:

```sh
docker compose down
```

## Admin password

The eXist-db admin password is empty in a fresh database. Set `EXIST_ADMIN_PASSWORD` in [.env](.env) before the first start and the publisher container will set it as soon as eXist-db is up (see [exist-init](exist-init)). If an app creates a `tei` user, you can set its password via `EXIST_TEI_PASSWORD` as well. The passwords are only applied while the admin password in the database volume is still empty, so changing them later has no effect on an existing database. Write a literal `$` as `$$`.

## Resource limits and protection

The publisher container is limited to `MEM_LIMIT` (default `4g`) and the Java heap to 65% of that, so an out-of-memory error restarts the container instead of taking down the host. eXist-db uses 20 database connections.

The nginx configuration in `nginx/conf/` adds some protection which proved necessary on public servers:

* `00-limits.conf`: maps for AI crawler user agents and vulnerability-scan URLs, connection limits per client address (8) and per virtual host (16)
* `block-probes.inc`: closes requests for `.env`, `.git`, WordPress, PHP and similar paths without forwarding them to eXist-db
* `document-cache-params.inc`, `document-block-bots.inc`: generated documents (PDF, EPUB, print, LaTeX, docx, markdown) are cached for 7 days and rate limited; AI crawlers get a 429 except for markdown
* `00-cache.conf`: the proxy cache. The homepage (`/index.html`) is cached for 10 minutes and `/api/parts/` responses for 7 days (revalidated with eXist-db)

## Customize the docker image

The default configuration runs the plain jinks image. Instead you may want to build and deploy a custom application on top of it. Clone or fork `tei-publisher-docker-compose` to apply some modifications. The included [Dockerfile](Dockerfile) builds one app from a git repository and adds it to the jinks image. It is used by the override file [docker-compose.build.yml](docker-compose.build.yml):

```sh
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

If you already have a ready-made image, just set `PUBLISHER_IMAGE` in [.env](.env) instead.


**Note**: if you already have a Dockerfile in your app repository, change `BUILD_CONTEXT` in [.env](.env) to point to the git repository in which your Dockerfile resides. If it is a private repository, it may require an access token (see the commented out examples). You can set tokens in the [.env](.env) file as well. You may then skip the rest of this chapter and continue reading [below](#configure-a-remote-server).

For the included `Dockerfile` we use configuration variables to point to the application to be built. The relevant variables start with `APP_` and should be set in the [.env](.env) environment file:

```sh
# Image the app is added to
BASE_IMAGE=ghcr.io/eeditiones/jinks:latest
# Name of the custom app to include - should correspond to the name of the repository
APP_NAME=tei-publisher-app
# Tag or branch to build
APP_TAG_OR_BRANCH=master
# GIT repository to clone the app from
APP_REPO=https://github.com/eeditiones/tei-publisher-app.git
```

Change the three `APP_` variables to point to your git repo, a tag/branch on it (e.g. `master`), and the name of the app. The latter should correspond to the repository name. You will probably also want to set `ROOT_PATH` to your app (see [below](#change-the-server-root-context)).

If your app **requires additional resources**, for example, because you keep your data files in a separate data package, you will have to modify the `Dockerfile` to include the necessary extra build steps.

To test your changed configuration locally, rebuild and restart the services (see commands below).

## Configure a remote server

Rent a cloud server which ideally has docker enabled. There are various offers on the market. A good specification would include 4 gb of RAM and 2 vCPU, which you can get for less than 10 Euro per month. We recommend to select a service which already provides a pre-configured docker installation as part of the operating system. Installing docker by hand is easily possible, but addressing security concerns in the right way requires care and a bit of reading. It saves some work if the provider has already dealt with this.

Once you have root access to your server, ssh into it and clone the docker compose configuration repository.

Configuring the server requires four steps:

1. modify `docker-compose.yml` to set the domain name and root path
2. enable the HTTP proxy configuration
3. launch the service once to acquire an SSL certificate
4. enable the HTTPS proxy configuration

### 1. Modify `docker-compose.yml`

Assuming that you have a domain name for the server, edit [.env](.env) and set `SERVER_NAME`:

```sh
# eXist-db path the root of the server will be mapped to
ROOT_PATH=/exist/apps/jinks
# Name of the server - irrelevant on localhost
SERVER_NAME=example.com
```

`ROOT_PATH` should correspond to the database path under which your application is found.

### 2. Enable HTTP proxy config

For security reasons we always hide eXist-db and TEI Publisher behind a proxy. The proxy redirects incoming requests to the configured services and blocks everything else. Our setup uses 3 configuration templates (the locations they share are in `publisher-locations.inc.template`):

|Template file | Description |
|---------|----------|
| localhost.conf.template | default (enabled) for local testing only |
| default.conf.off | disabled template for HTTP access |
| default.ssl.conf.off | disabled template for HTTPS access |

For the full server setup, we have to disable the localhost configuration and enable the HTTP configuration to acquire an SSL certificate. Once this is done, we can enable the HTTPS configuration as well.

Go to the `nginx/templates` directory and either remove `localhost.conf.template` or rename it to `localhost.conf.off`, then rename `default.conf.off` to `default.conf.template`.

### 3. Acquire an SSL certificate

Before we can fully access the server, we need to get an SSL certificate. To do so:

1. Start the services (`docker compose up -d`)
2. Run the following command to request an SSL certificate for your domain, replacing the final `example.com` with your domain name:
   ```sh
   docker compose run --rm  certbot certonly --webroot --webroot-path /var/www/certbot/ -d example.com
   ```

   This will ask you for an email address, verify your server and store certificate files into `certbot/conf/`.

### 4. Enable HTTPS proxy config

Rename `nginx/templates/default.ssl.conf.off` to `nginx/templates/default.ssl.conf.template`, thus enabling the ssl configuration.

Now restart the services:

   ```sh
   docker compose restart
   ```

## Useful docker compose commands

Build (without cache) and start all services

```sh
docker compose -f docker-compose.yml -f docker-compose.build.yml build --no-cache
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d
```

Pull the latest jinks image and restart:

```sh
docker compose pull publisher && docker compose up -d
```

Display log output of the TEI Publisher service (i.e. eXist-db logs)

```sh
docker compose logs publisher
```

Stop all services:

```sh
docker compose down
```

## Change the server root context

The two most important configuration settings can be found in [.env](.env):

```
# eXist-db path the root of the server will be mapped to. Specifying a path here
# will map the root to one single app; other apps stay reachable below /exist/apps/.
# Change to empty string if you want to expose the entire database.
ROOT_PATH=/exist/apps/jinks
# App context path: set to 'auto' if apps should be exposed under their full path
# (e.g. /exist/apps/tei-publisher), empty if a single app is mapped to the root.
CONTEXT_PATH=auto
```

The `ROOT_PATH` variable specifies which database URLs will be mapped to the root, in other words: what users will see if they access the root of the server (e.g. `http://localhost`). With the setting above, users see jinks. Other applications in the database are still available under their full path, e.g. `http://localhost/exist/apps/my-edition/`.

To map the root to your own app, set `ROOT_PATH` to its path (e.g. `/exist/apps/my-edition`). To expose the entire database, set `ROOT_PATH` to the empty string and keep `CONTEXT_PATH=auto`.

## Certificate Renewal

The LetsEncrypt SSL certificate issued above will only be valid for a certain duration and needs to be renewed from time to time. We'll thus install a cron job, which calls the script `certbot-renew.sh` once every day to check if the certificate needs to be renewed.

Register a cron job to call this script once a day. Call `crontab -e` and add a line:

```
59 18 * * * /root/my-edition-docker/certbot-renew.sh
```
replacing `/root/my-edition-docker` with the correct path to wherever you cloned the configuration.

## Backing up eXist-db

If you would like to create regular backups of the data in your eXist-db:

1. edit `docker-compose.yml` and enable the volume mapping for `/exist/backup`:
   ```
   # uncomment to map eXist-db backups to local directory
   - ./backup:/exist/backup
   ```
2. retrieve the eXist-db configuration file from the running docker container with
   ```
   docker compose cp publisher:/exist/etc/conf.xml .
   ```
3. edit conf.xml and find the section referring to consistency checks and backups. Uncomment the system job, specify the backup directory and a time (cron syntax) to trigger the backup:
   ```xml
   <job type="system" name="check1" 
      class="org.exist.storage.ConsistencyCheckTask"
      cron-trigger="0 0 4 * * ?">
      <parameter name="output" value="/exist/backup"/>
      <parameter name="backup" value="yes"/>
      <parameter name="incremental" value="no"/>
      <parameter name="incremental-check" value="no"/>
      <parameter name="max" value="2"/>
   </job>
   ```
4. copy the `conf.xml` back to the docker container:
   ```
   docker compose cp conf.xml publisher:/exist/etc
   ```
5. restart the container:
   ```
   docker compose restart publisher
   ```

## Using IIIF

The included cantaloupe IIIF server reads images from a file system directory. By default this is mapped to the folder `iiif` in the same directory as the docker-compose configuration:

```yaml
volumes:
   - ./iiif:/imageroot
```

To change the directory, replace the path before the ':'.

To access cantaloupe's admin interface, edit [docker-compose.yml](docker-compose.yml), set `CANTALOUPE_ENDPOINT_ADMIN_ENABLED` to `true`, define a secret and enable the port mapping:

```sh
cantaloupe:
    image: uclalibrary/cantaloupe:5.0.5-7
    environment:
      CANTALOUPE_ENDPOINT_ADMIN_ENABLED: false
      CANTALOUPE_ENDPOINT_ADMIN_SECRET: my_admin_pass
    volumes:
      - ./iiif:/imageroot
    # comment in to enable access to cantaloupe on port 8182, including admin interface
    # ports:
    #   - 8182:8182

```

The admin interface will be available at port 8182: http://localhost:8182/admin.

# Ansible setup

[Ansible](https://docs.ansible.com/) is an automation framework for managing servers. It uses an ssh connection between the controlling machine and the server to automatically work through a sequence of setup tasks (the **playbook**). Benefits:

* no manual steps required
* you can rebuild the same setup any time on the same or different target machines
* we can create more complex setups, i.e. multiple applications running on the same eXist-db database, each accessible through its own domain name. For example, you could expose app1 under https://app1.com and app2 under https://app2.com.

The obvious downside is that you need ansible installed on your local machine. Check the [official documentation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible) for instructions.

Once you have ansible (check if you can execute the command `ansible-playbook`), clone this repository to your local machine (in ansible terms called **the control node**) and change into the `ansible` subdirectory.

You obviously also need a server into which you can ssh. It is recommended to add the ssh configuration into your personal `.ssh/config`. Furthermore you should have a DNS entry mapped to this server before you start.

Nearly all settings are configured via configuration files. First edit [ansible/hosts](ansible/hosts) and provide the name of you ssh key configuration:

```yaml
all:
    hosts:
        # should point to an ssh configuration entry in your .ssh/config
        workshop
```

Next open [ansible/variables.yml](ansible/variables.yml) to specify the domains to be served and, optionally, apps to be built. By default the latest jinks image is deployed without additional apps. Most of the settings are similar (if not identical) to the once used for the simple docker-compose setup explained above. 

## Define the apps to be built

By default `publisher.image` (`ghcr.io/eeditiones/jinks:latest`) is pulled and run as is. To add your own apps, list them under `publisher.apps`. Ansible then generates a Dockerfile which builds each app and adds it on top of `publisher.base_image`:

```yaml
publisher:
  base_image: ghcr.io/eeditiones/jinks:latest
  apps:
    # Name of the custom app to include - should correspond to the name of the repository
    - name: "my-edition"
      # Tag or branch to build
      tag_or_branch: "main"
      # GIT repository to clone the app from
      repo: "https://github.com/me/my-edition.git"
```

The memory limit of the publisher container is set with `publisher.memory` (default `4g`); the Java heap gets 65% of it.

## Map application paths to server domains

One or more apps can then be mapped to a domain in the `domains` section:

```yaml
# the domains to be served by the proxy. Each domain may map to a different app and root path
# within the same eXist-db instance
domains:
  - name: publisher
    # eXist-db path the root of the server will be mapped to. Specifying a path here
    # will map the root to one single app. Change to empty string if you want to expose the
    # entire database and also set CONTEXT_PATH=auto below.
    root: /exist/apps/jinks
    # if root is mapped to a single app, should requests to /exist/apps/ still be allowed?
    allow_apps: true
    # the name the server should listen to
    hostname: workshop.teipublisher.com
    # other host names which permanently redirect to `hostname`
    aliases: [www.workshop.teipublisher.com]
```

The `name` can be any internal name used to identify the mapping. `root` should contain the URL path into eXist-db which should be mapped to the root of the domain. `hostname` is the domain name the server should listen to. Requests to any of the `aliases` are redirected to `hostname`; a certificate is requested for each of them. The nginx protection and caching described [above](#resource-limits-and-protection) are applied to every domain.

The ansible playbook will automatically try to register an SSL certificate for each domain. This service has rate limits, so if you hit it too often during testing, you'll be blocked for a while. To prevent this, set the variable `use_staging` in the `cert` section to `true`. This means your SSL certificates won't be valid and your browser will complain, but you can test out if the process runs through properly.

## Enabling/disabling services

By default the generated configuration will also start the IIIF image service and the Named Entity Recognition service. If you don't need those, disable them in the `services` section:

```yaml
# which optional services should be started?
services:
  # IIIF image service
  iiif: false
  # Named entity recognition
  ner: true
```

## Run ansible

Once you are done editing the configuration, launch the ansible playbook with the following command:

```sh
ansible-playbook -i hosts site.yml
```

You will be prompted to specify a password for the eXist-db admin user. Choosing a strong admin password is highly recommended. It is written to the `.env` file on the server (readable by root only) and applied by the publisher container on the first start of a fresh database. The password must not contain a single quote. An optional password for the `tei` user can be set via `publisher.tei_pass`.

**Note**: if apps are configured, the generated Dockerfile will be saved to `ansible/Dockerfile.generated`. If you would like to use it for local testing, replace the `Dockerfile` in the parent directory with this one. You can then test on your local machine as described [above](#customize-the-docker-image).

## Update

If you wish to update jinks and all apps to newer versions, but leave the generated docker and nginx configurations untouched, call

```sh
ansible-playbook -i hosts update.yml
```

**Note** that this will explicitely remove any data added to the database by users and pull or rebuild the docker image! The admin password stored in `.env` is applied again to the fresh database.

## Rebuild

To rebuild everything without having to renew the SSL certificate, call

```sh
ansible-playbook -i hosts --skip-tags clean,cert site.yml
```

This will prevent the existing directory from being removed and leaves the SSL certificate untouched. The docker and nginx configurations will still be recreated.

## Other commands

Run checks only:

```sh
ansible-playbook -i hosts --tags check site.yml
```

(Re-)generate Dockerfile locally:

```sh
ansible-playbook -i hosts --tags dockerfile site.yml
```