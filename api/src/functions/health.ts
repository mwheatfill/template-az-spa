import "@apvee/azure-functions-openapi";
import { app, type HttpRequest, type HttpResponseInit } from "@azure/functions";
import { z } from "zod";
import { getPrincipal } from "../../_shared/auth.js";
import { ok } from "../../_shared/http.js";

const HealthResponse = z.object({
  status: z.literal("ok"),
  service: z.string(),
  timestamp: z.iso.datetime(),
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

app.openapiPath("health", "Health check", {
  handler: health,
  methods: ["GET"],
  authLevel: "anonymous",
  route: "health",
  description:
    "Liveness check. Returns service identity, build version, and the calling user if signed in.",
  operationId: "getHealth",
  tags: ["System"],
  responses: [
    {
      httpCode: 200,
      description: "Service is alive.",
      schema: HealthResponse,
    },
  ],
});
