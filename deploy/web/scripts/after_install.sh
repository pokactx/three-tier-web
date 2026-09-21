#!/bin/bash
set -euo pipefail
chmod -R a+rX /usr/share/nginx/html
systemctl reload nginx
