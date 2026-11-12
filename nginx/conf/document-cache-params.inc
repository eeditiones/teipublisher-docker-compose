# Shared by document-export cache locations. Not named *.conf so
# nginx does not auto-load this at the http level.

# Per-IP cap: a human can start a few downloads; overlapping crawler
# retries (the 499 storm) get 429 instead of another EPUB generation.
limit_req zone=doc_export_ip burst=10 nodelay;
limit_conn doc_export_conn 3;

# If the client gives up, still finish and fill the cache so retries HIT.
proxy_ignore_client_abort on;

proxy_set_header   Host $host;
proxy_set_header   X-Real-IP $remote_addr;
proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Host $server_name;
proxy_ssl_server_name on;
proxy_cookie_path /exist /;
client_max_body_size  512m;

# Exports (especially EPUB) can take minutes; wait for the first
# generation instead of stampeding eXist.
proxy_read_timeout 5m;
proxy_send_timeout 5m;
proxy_cache_lock_timeout 5m;

expires 7d;
proxy_cache_key "$request_method$uri$is_args$arg_odd$arg_source$arg_template";
proxy_cache page_cache;
# Do not use "any" — that would cache 502s from crashes.
proxy_cache_valid 200 301 302 304 7d;
proxy_cache_valid 400 401 404 0m;
proxy_cache_lock on;
proxy_cache_min_uses 1;
proxy_ignore_headers Set-Cookie Cache-Control Vary Expires;
proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
add_header X-Proxy-Cache $upstream_cache_status;
