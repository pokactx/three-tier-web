import { randomUUID } from "node:crypto";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { createPrisma } from "./db";
import { todoRoutes } from "./todos";

function loaded(name: string): boolean {
  const v = process.env[name];
  return typeof v === "string" && v.length > 0;
}

const prisma = await createPrisma().catch((err: unknown) => {
  console.error("prisma init failed", err);
  return null;
});

const app = new Hono();

app.get("/health", (c) => c.text("ok"));

app.get("/api/status", async (c) => {
  let db = false;
  if (prisma) {
    try {
      await prisma.$queryRaw`SELECT 1`;
      db = true;
    } catch {
      db = false;
    }
  }
  return c.json({
    secretsLoaded: loaded("SESSION_SECRET") && loaded("THIRD_PARTY_API_KEY"),
    db,
  });
});

app.get("/api/upload-url", async (c) => {
  const bucket = process.env.UPLOAD_BUCKET;
  if (!bucket) return c.json({ error: "UPLOAD_BUCKET missing" }, 500);
  const key = `uploads/${randomUUID()}`;
  const s3 = new S3Client({ region: process.env.AWS_REGION ?? "ap-northeast-1" });
  const url = await getSignedUrl(
    s3,
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: "application/octet-stream",
    }),
    { expiresIn: 300 },
  );
  return c.json({ url, key });
});

app.route("/api/todos", todoRoutes(prisma));

const port = Number(process.env.PORT ?? "3000");
serve({ fetch: app.fetch, port }, (info) => {
  console.log(`hono listen ${info.port}`);
});
