# Close vulnerability-scan URLs before they are proxied. Safe use of if: only return.
if ($is_probe_uri) {
    return 444;
}

# Per address, and all addresses on this vhost together. See 00-limits.conf.
limit_conn per_ip_conn 8;
limit_conn exist_conn 16;
