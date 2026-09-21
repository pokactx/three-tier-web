#!/usr/bin/env bash
set -euo pipefail
echo "アプリの配布は GitHub ${1:-main} → CodePipeline → CodeDeploy。"
echo "このスクリプトは使わない。インフラ変更は terraform apply（人間）。"
exit 1
