import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";
import { PrismaClient } from "@prisma/client";

type RdsSecret = {
  username?: string;
  password?: string;
  port?: number;
};

function encode(value: string): string {
  return encodeURIComponent(value);
}

export async function resolveDatabaseUrl(): Promise<string> {
  const fromEnv = process.env.DATABASE_URL;
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;

  const host = process.env.RDS_PRIMARY;
  const arn = process.env.RDS_SECRET_ARN;
  if (!host || !arn) {
    throw new Error("DATABASE_URL or RDS_PRIMARY+RDS_SECRET_ARN required");
  }

  const region = process.env.AWS_REGION ?? "ap-northeast-1";
  const sm = new SecretsManagerClient({ region });
  const res = await sm.send(new GetSecretValueCommand({ SecretId: arn }));
  if (!res.SecretString) throw new Error("RDS secret empty");

  const secret = JSON.parse(res.SecretString) as RdsSecret;
  if (!secret.username || !secret.password) throw new Error("RDS secret incomplete");

  const port = secret.port ?? 3306;
  return `mysql://${encode(secret.username)}:${encode(secret.password)}@${host}:${port}/app`;
}

export async function createPrisma(): Promise<PrismaClient> {
  const url = await resolveDatabaseUrl();
  process.env.DATABASE_URL = url;
  return new PrismaClient({ datasources: { db: { url } } });
}
