import "@apvee/azure-functions-openapi";
import { app } from "@azure/functions";

app.openapiSetup({
  info: {
    title: process.env.OPENAPI_TITLE ?? "Tier 1 SPA API",
    version: process.env.OPENAPI_VERSION ?? "1.0.0",
    description:
      "Authoritative API contract for this app. Consumed by the SPA, agent layers (Copilot plugins, MCP servers), and any future clients.",
  },
  routePrefix: "api",
  versions: ["3.1.0"],
  formats: ["json", "yaml"],
  swaggerUI: { enabled: true },
});

import "./functions/health.js";
