# 中規模 3 層 Web — Terraform

日本の現場で IaC を武器にするなら、まず Terraform（HCL + AWS provider）を手で書けることが現実的な基準になる。このリポジトリはそれを学ぶための 3 層構成である。

`ap-northeast-1`、マルチ AZ（`1a` / `1c`）。

Drive 上の `3層アーキテクチャ.drawio`（最終版）を意図した構成だが、この環境の Drive アカウントからは当該ファイルを読めなかった。以下はユーザーが提示した最終版の要素を仕様として固定したもの。図と食い違う点があれば README を先に直す。

仕様の正本はこの README。

## 構成

```
インターネット
  └─ CloudFront + WAF（エッジ、HTTPS）─ 表の入口
       ├─ /uploads/* → S3（OAC、静的 GET）
       └─ それ以外 → 公開 ALB（秘密ヘッダ必須）
            ├─ /api/* → App ASG（非公開）─ RDS Primary
            │                              └─ 同期 → Standby（アプリは見ない）
            └─ それ以外 → Web ASG（非公開、nginx が SPA）

公開 ALB は CloudFront からだけ到達（SG + 秘密ヘッダ）。ALB URL 直アクセスは不可。
Web / API のパス分岐は公開 ALB のリスナールール。nginx は静的配信と /health だけ。
App ─ presigned URL ─ ブラウザが S3 へ直 PUT
App / Web ─ S3 は Gateway Endpoint（NAT を使わない）
App ─ 外部 API は NAT（AZ ごとに 1 台）
```

S3 は VPC の外。アップロード済みオブジェクトの GET は CloudFront + OAC。SPA と `/api/` は CloudFront から公開 ALB へ（ビューアは HTTPS、オリジンへは HTTP + `X-Origin-Verify`）。ALB がパスで Web と App に分ける。アップロードは App が署名し、ブラウザがインターネット経由で PUT する。バケットを VPC エンドポイント専用に閉じると直 PUT が死ぬので、閉じない。

## ネットワーク

| 帯 | CIDR | AZ | 経路 |
|---|---|---|---|
| VPC | `10.0.0.0/16` | — | — |
| 公開 | `10.0.0.0/24`, `10.0.1.0/24` | 1a / 1c | `0.0.0.0/0` → IGW。NAT×2 と公開 ALB |
| Web 非公開 | `10.0.10.0/24`, `10.0.11.0/24` | 1a / 1c | `0.0.0.0/0` → 同 AZ の NAT。S3 → Gateway Endpoint |
| App 非公開 | `10.0.20.0/24`, `10.0.21.0/24` | 1a / 1c | 同上 |
| データ | `10.0.30.0/24`, `10.0.31.0/24` | 1a / 1c | インターネットなし。RDS のみ |

## セキュリティグループ

Allow のみ。サブネットではなく ENI に付ける。

| SG | 入 | 出 |
|---|---|---|
| 公開 ALB | 80 を CloudFront プレフィックスリストのみ。HTTP は秘密ヘッダ必須 | Web:80、App:80 |
| Web | 公開 ALB から 80 | 443（更新・SSM・外部） |
| App | 公開 ALB から 80 | RDS:3306、443（S3 署名用 SDK・外部 API・SSM） |
| RDS | App から 3306 | なし（必要なら応答のみ） |

## アプリ

- `web/`: Vite + React + TypeScript。パッケージは bun。ブラウザに出るので **シークレットを置かない**（`VITE_*` にも載せない）。Todo UI
- `app/`: Hono + Prisma。ローカルは bun。EC2 上は成果物を Node で動かす。`/health`、`/api/status`（シークレットの有無と DB 到達）、`/api/todos`、`/api/upload-url`
- Prisma は RDS MySQL **Primary** だけを見る。接続 URL はランタイムで Secrets Manager から組み立てる（パスワードを systemd の EnvironmentFile に書かない）
- 公開 ALB リスナールール: `X-Origin-Verify` かつ `/api/*` → App。同ヘッダのその他 → Web。ヘッダ無しは 403
- Web（nginx）は SPA と `/health` だけ。`/api/` は reverse proxy しない
- user_data は nginx / Node / CodeDeploy エージェントとシークレットの箱だけ。アプリ本体は CodeDeploy が入れる。未配置なら `/health` フォールバック
- App の成果物は ESM。`package.json` に `"type": "module"` を含める
- アプリの配布は GitHub `main` → CodePipeline → CodeBuild → CodeDeploy（Web のあと App）。インフラは `terraform apply`（人間）

## シークレット（運用）

- 値は Terraform 変数・tfvars・user_data・フロントに書かない
- user_data に載せてよいのは ARN とホスト名だけ。user_data はコンソールから読める
- App ランタイムは Secrets Manager（`SESSION_SECRET`、`THIRD_PARTY_API_KEY`）。起動時にインスタンスロールで取得し、`/etc/app/secrets.env`（0600）へ。systemd の `EnvironmentFile`
- 初期バージョンだけ Terraform が作る。以降は `ignore_changes`。ローテはコンソールまたは `put-secret-value`（人間）
- RDS マスタも Secrets Manager。Hono は起動時に Get し、Primary アドレスだけ見る
- フロントはシークレットの有無しか見ない。値は返さない

## 計算・データ

- 公開 ALB: internet-facing だが CloudFront オリジン専用（HTTP:80、秘密ヘッダ）。パスで Web / App のターゲットグループへ。アクセスログを logs バケットへ
- Web ASG: 起動テンプレート、IMDSv2 必須、ヘルスチェック `ELB`、最低 2（各 AZ 1）、Rolling instance refresh
- App ASG: 同上。アプリは RDS **Primary エンドポイントだけ** を見る。Standby には接続しない
- RDS MySQL Multi-AZ。暗号化、非公開。DB 名 `app`。CodeDeploy の AfterInstall で `prisma migrate deploy`
- インスタンスロール: SSM、CodeDeploy エージェント、artifact バケットの Get。App は uploads の Put/Get と Secrets Manager の当該シークレットだけ Get
- SSH は開けない。操作は Session Manager

## エッジ

- S3: パブリックアクセス全面ブロック、SSE-S3、CORS でブラウザ PUT
- CloudFront: 既定オリジンは公開 ALB（キャッシュしない）。`/uploads/*` だけ OAC で S3 GET。WAF を関連付け。証明書は `*.cloudfront.net` のデフォルト
- WAF（CLOUDFRONT）: `us-east-1` プロバイダ。Common Rule Set + Known Bad Inputs + レート制限
- Route 53: `domain_name` と `hosted_zone_id` があるときだけ、ドメインと `static.` サブドメインを CloudFront へ ALIAS

## Terraform で押さえる点

- AZ は `for_each`（`count` で index 依存にしない）
- S3 は bucket 本体と Public Access Block / CORS / 暗号化 / policy を分ける（AWS provider 4 以降の形）
- CloudFront 用 WAF は `provider = aws.useast1`
- user_data は `templatefile()`。nginx の `$uri` はテンプレートでは `$${uri}`
- パスワードと App シークレットは Secrets Manager。tf にリテラルを書かない
- 状態ファイルはコミットしない。チーム運用では S3 + DynamoDB ロック（`backend.hcl.example`。同じ state では作らない）
- ALB アクセスログと CloudWatch アラーム（5xx / unhealthy）を付ける
- SG 同士の Allow はインラインではなく `aws_security_group_rule`。参照元ルールを先に消してから参照先 SG を消せる
- Auto Scaling はアカウントのサービスリンクロール `AWSServiceRoleForAutoScaling` で ALB を検証する。Terraform が無ければ作る。CLI ユーザーに `iam:CreateServiceLinkedRole` が無いときは、管理者で一度だけ作る

## 意図的に含めないもの

- NAT を 1 台に減らすこと
- アプリから Standby への接続
- S3 を VPC 内に置くこと
- バケットを Gateway Endpoint 専用に閉じること
- 自動 `terraform apply`（人間が実行する）
- 同じ state でリモートバックエンド用バケットを作ること（鶏と卵）
- フロントの `VITE_*` にシークレットを置くこと
- 費用の図への記載
- nginx で `/api/` を reverse proxy すること
- Web と App の間の内部 ALB
- ECS / Fargate
- パイプラインからの `terraform apply`
- CodeBuild から RDS への migrate
- blue/green 用の第二 ASG

## CI/CD

アプリだけパイプライン。インフラは載せない。

```
GitHub main
  → CodePipeline（V2、QUEUED）
    → CodeBuild（bun、VPC に入れない）
    → CodeDeploy Web（in-place、OneAtATime、ALB ヘルス待ち）
    → CodeDeploy App（同上。AfterInstall で migrate）
```

新しい ASG インスタンスは直近の成功リビジョンをエージェントが取る。

1. リポは `pokactx/three-tier-web`。`terraform.tfvars` の `github_repository` は example と同じでよい
2. `terraform apply`（人間）
3. CodeStar Connections が PENDING ならコンソールで GitHub を承認し、もう一度 apply
4. `main` へ push するとビルドと配布が走る

ローカル確認は従来どおり bun。本番へは push だけ。`scripts/publish.sh` は使わない。

## 動かし方

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan
# 適用は人間が terraform apply
```

AWS 認証は既存の `aws login`（長期キーは使わない）。リージョンは `ap-northeast-1`。

`pokactx` に `iam:CreateServiceLinkedRole` が無い場合、apply の前に管理者で一度だけ:

```bash
aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com
terraform -chdir=terraform import aws_iam_service_linked_role.autoscaling autoscaling.amazonaws.com
```

ローカルのアプリ:

```bash
docker compose up -d
cp app/.env.example app/.env
cd app && bun install && bun run migrate && bun run dev
cd web && bun install && bun run dev
```

ローカル MySQL は `docker compose`（`127.0.0.1:3306`、DB `app`）。AWS 上では App が RDS シークレットから `DATABASE_URL` を組み立て、CodeDeploy AfterInstall で migrate する。RDS は非公開なのでノート PC から直接は繋がらない。
