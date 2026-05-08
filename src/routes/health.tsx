import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const HealthResponseSchema = z.object({
  status: z.literal("ok"),
  service: z.string(),
  timestamp: z.string(),
  version: z.string().optional(),
});

async function fetchHealth() {
  const res = await fetch("/api/health");
  if (!res.ok) throw new Error(`Health check failed: ${res.status}`);
  return HealthResponseSchema.parse(await res.json());
}

export const Route = createFileRoute("/health")({
  component: HealthPage,
});

function HealthPage() {
  const { data, isPending, isError, error } = useQuery({
    queryKey: ["health"],
    queryFn: fetchHealth,
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Health</h1>
        <p className="text-muted-foreground">
          Calls <code className="rounded bg-muted px-1 py-0.5 text-xs">/api/health</code> through
          TanStack Query. Validates the Function tier is responding.
        </p>
      </div>
      <Card>
        <CardHeader>
          <CardTitle>API status</CardTitle>
          <CardDescription>Live response from the managed Functions endpoint.</CardDescription>
        </CardHeader>
        <CardContent>
          {isPending && <p className="text-muted-foreground">Checking…</p>}
          {isError && <p className="text-destructive">Error: {error.message}</p>}
          {data && (
            <pre className="overflow-x-auto rounded bg-muted p-4 text-sm">
              {JSON.stringify(data, null, 2)}
            </pre>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
