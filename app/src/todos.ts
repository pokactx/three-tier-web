import type { PrismaClient } from "@prisma/client";
import { Hono } from "hono";

function unavailable() {
  return { error: "db unavailable" } as const;
}

function parseTitle(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const title = value.trim();
  if (title.length === 0 || title.length > 255) return null;
  return title;
}

export function todoRoutes(prisma: PrismaClient | null) {
  const r = new Hono();

  r.get("/", async (c) => {
    if (!prisma) return c.json(unavailable(), 503);
    const todos = await prisma.todo.findMany({ orderBy: { createdAt: "desc" } });
    return c.json(todos);
  });

  r.post("/", async (c) => {
    if (!prisma) return c.json(unavailable(), 503);
    const body = (await c.req.json().catch(() => null)) as { title?: unknown } | null;
    const title = parseTitle(body?.title);
    if (!title) return c.json({ error: "title required (1-255)" }, 400);
    const todo = await prisma.todo.create({ data: { title } });
    return c.json(todo, 201);
  });

  r.patch("/:id", async (c) => {
    if (!prisma) return c.json(unavailable(), 503);
    const id = c.req.param("id");
    const body = (await c.req.json().catch(() => null)) as { title?: unknown; done?: unknown } | null;
    const data: { title?: string; done?: boolean } = {};
    if (body && "title" in body) {
      const title = parseTitle(body.title);
      if (!title) return c.json({ error: "title required (1-255)" }, 400);
      data.title = title;
    }
    if (body && "done" in body) {
      if (typeof body.done !== "boolean") return c.json({ error: "done must be boolean" }, 400);
      data.done = body.done;
    }
    if (data.title === undefined && data.done === undefined) {
      return c.json({ error: "nothing to update" }, 400);
    }
    try {
      const todo = await prisma.todo.update({ where: { id }, data });
      return c.json(todo);
    } catch {
      return c.json({ error: "not found" }, 404);
    }
  });

  r.delete("/:id", async (c) => {
    if (!prisma) return c.json(unavailable(), 503);
    const id = c.req.param("id");
    try {
      await prisma.todo.delete({ where: { id } });
      return c.body(null, 204);
    } catch {
      return c.json({ error: "not found" }, 404);
    }
  });

  return r;
}
