import { FormEvent, useCallback, useEffect, useState } from "react";

type Todo = {
  id: string;
  title: string;
  done: boolean;
  createdAt: string;
};

type Status = {
  secretsLoaded: boolean;
  db: boolean;
};

async function readError(res: Response): Promise<string> {
  const body = (await res.json().catch(() => null)) as { error?: string } | null;
  return body?.error ?? `status ${res.status}`;
}

export function App() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [title, setTitle] = useState("");
  const [status, setStatus] = useState<Status | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [todoRes, statusRes] = await Promise.all([fetch("/api/todos"), fetch("/api/status")]);
    if (!todoRes.ok) throw new Error(await readError(todoRes));
    const items = (await todoRes.json()) as Todo[];
    const st = statusRes.ok ? ((await statusRes.json()) as Status) : null;
    setTodos(items);
    setStatus(st);
    setError(null);
  }, []);

  useEffect(() => {
    let cancelled = false;
    load().catch((e: unknown) => {
      if (!cancelled) setError(e instanceof Error ? e.message : "load failed");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    const value = title.trim();
    if (!value || busy) return;
    setBusy(true);
    try {
      const res = await fetch("/api/todos", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: value }),
      });
      if (!res.ok) throw new Error(await readError(res));
      setTitle("");
      await load();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "create failed");
    } finally {
      setBusy(false);
    }
  }

  async function onToggle(todo: Todo) {
    if (busy) return;
    setBusy(true);
    try {
      const res = await fetch(`/api/todos/${todo.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ done: !todo.done }),
      });
      if (!res.ok) throw new Error(await readError(res));
      await load();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "update failed");
    } finally {
      setBusy(false);
    }
  }

  async function onDelete(id: string) {
    if (busy) return;
    setBusy(true);
    try {
      const res = await fetch(`/api/todos/${id}`, { method: "DELETE" });
      if (!res.ok) throw new Error(await readError(res));
      await load();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "delete failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main>
      <h1>Todo</h1>
      <p className="lead">フロントは /api だけ呼ぶ。永続化は App → Prisma → RDS Primary。</p>

      <form onSubmit={onCreate}>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="やること"
          maxLength={255}
          disabled={busy}
        />
        <button type="submit" disabled={busy || title.trim().length === 0}>
          追加
        </button>
      </form>

      {error ? <p className="error">{error}</p> : null}

      {todos.length === 0 && !error ? <p className="empty">まだありません</p> : null}

      <ul>
        {todos.map((todo) => (
          <li key={todo.id} className={todo.done ? "done" : undefined}>
            <label>
              <input type="checkbox" checked={todo.done} onChange={() => onToggle(todo)} disabled={busy} />
              <span>{todo.title}</span>
            </label>
            <button type="button" className="danger" onClick={() => onDelete(todo.id)} disabled={busy}>
              削除
            </button>
          </li>
        ))}
      </ul>

      <p className="meta">
        db: {status ? (status.db ? "ok" : "down") : "…"} / secrets:{" "}
        {status ? (status.secretsLoaded ? "yes" : "no") : "…"}
      </p>
    </main>
  );
}
