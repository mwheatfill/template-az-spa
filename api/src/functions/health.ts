import { registerFunction } from "@apvee/azure-functions-openapi";
import type { HttpRequest, HttpResponseInit } from "@azure/functions";
import { z } from "zod";
import { getPrincipal } from "../../_shared/auth.js";
import { ok } from "../../_shared/http.js";

const HealthResponse = z.object({
  status: z.literal("ok"),
  service: z.string(),
  timestamp: z.string().datetime(),
  version: z.string(),
  user: z.string().nullable(),
});

export async function health(req: HttpRequest): Promise<HttpResponseInit> {
  const principal = getPrincipal(req);
  return ok({
    status: "ok" as const,
    service: "api",
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION ?? "dev",
    user: principal?.userDetails ?? null,
  });
}

registerFunction("health", "Health check", {
  handler: health,
  methods: ["GET"],
  authLevel: "anonymous",
  azureFunctionRoutePrefix: "api",
  route: "health",
  description:
    "Liveness check. Returns service identity, build version, and the calling user if signed in.",
  operationId: "getHealth",
  tags: ["System"],
  responses: {
    "200": {
      description: "Service is alive.",
      content: {
        "application/json": { schema: HealthResponse },
      },
    },
  },
});
