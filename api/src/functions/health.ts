import { app, type HttpRequest, type HttpResponseInit } from "@azure/functions";
import { getPrincipal } from "../../_shared/auth.js";
import { ok } from "../../_shared/http.js";

export async function health(req: HttpRequest): Promise<HttpResponseInit> {
  const principal = getPrincipal(req);
  return ok({
    status: "ok",
    service: "api",
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION ?? "dev",
    user: principal?.userDetails ?? null,
  });
}

app.http("health", {
  route: "health",
  methods: ["GET"],
  authLevel: "anonymous",
  handler: health,
});
