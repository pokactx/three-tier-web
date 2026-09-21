#!/bin/bash
set -euo pipefail
set -a
# shellcheck disable=SC1091
source /etc/app/rds.env
set +a

RDS_JSON="$(aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${RDS_SECRET_ARN}" \
  --query SecretString \
  --output text)"
export DATABASE_URL="$(RDS_JSON="$RDS_JSON" RDS_HOST="${RDS_PRIMARY}" python3 - <<'PY'
import json
import os
import urllib.parse
raw = json.loads(os.environ["RDS_JSON"])
user = urllib.parse.quote(str(raw["username"]), safe="")
password = urllib.parse.quote(str(raw["password"]), safe="")
host = os.environ["RDS_HOST"]
port = raw.get("port", 3306)
print(f"mysql://{user}:{password}@{host}:{port}/app")
PY
)"
unset RDS_JSON

cd /opt/app
npm install --omit=dev
npx prisma migrate deploy
