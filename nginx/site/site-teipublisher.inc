# teipublisher.org only: extra locations for the main server block.
# Included via `includes` in ansible/variables.yml. Not named *.conf so nginx
# does not load it at http level.

# Keep the app's robots.txt and append the chronicle rule. Accept-Encoding
# is cleared so the addition module sees an uncompressed body. addition_types
# must include text/plain; the module otherwise only rewrites text/html.
location = /robots.txt {
  proxy_pass http://docker-publisher/exist/apps/tei-publisher/robots.txt;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Host $server_name;
  proxy_set_header Accept-Encoding "";
  proxy_ssl_server_name on;
  proxy_connect_timeout 3s;
  proxy_read_timeout 5s;
  proxy_intercept_errors on;
  error_page 500 502 504 =200 /internal/robots-chronicle.txt;
  add_after_body /internal/robots-chronicle.txt;
  addition_types text/plain application/octet-stream;
}

location = /internal/robots-chronicle.txt {
  internal;
  alias /etc/nginx/conf.d/robots-chronicle.txt;
  default_type text/plain;
}

# Exact match wins over the regex below, with and without a query string.
# Browsers may filter the chronicle. Crawlers may not: each query is another
# uncached render, and robots.txt alone does not stop a bot that already has the URL.
location = /exist/apps/wall-came-down/chronicle.html {
  if ($block_chronicle_query) {
    return 403;
  }
  proxy_pass http://docker-publisher$request_uri;
  proxy_redirect http://$host/exist/apps/wall-came-down/ /exist/apps/wall-came-down/;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Host $server_name;
  proxy_ssl_server_name on;
  proxy_cookie_path /exist /;
  client_max_body_size 512m;
  add_header X-Robots-Tag $chronicle_robots always;
}

# Old documentation URLs
location = /exist/apps/tei-publisher/documentation {
  return 301 https://tei-publisher.org/browse.html?collection=doc;
}
location = /exist/apps/tei-publisher/documentation/create-app {
  return 301 https://tei-publisher.org/doc/quickstart.xml;
}
location = /exist/apps/tei-publisher/documentation/installation {
  return 301 https://tei-publisher.org/doc/installation.xml;
}
location = /exist/apps/tei-publisher-home/index.html {
  return 301 https://tei-publisher.org/index.html;
}
