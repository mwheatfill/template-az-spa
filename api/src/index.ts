import {
  type OpenAPIObjectConfig,
  registerOpenAPIHandler,
  registerSwaggerUIHandler,
} from "@apvee/azure-functions-openapi";

import "./functions/health.js";

const openApiConfig: OpenAPIObjectConfig = {
  info: {
    title: process.env.OPENAPI_TITLE ?? "Tier 1 SPA API",
    version: process.env.OPENAPI_VERSION ?? "1.0.0",
    description:
      "Authoritative API contract for this app. Consumed by the SPA, agent layers (Copilot plugins, MCP servers), and any future clients.",
  },
};

const documents = [
  registerOpenAPIHandler("anonymous", openApiConfig, "3.1.0", "json"),
  registerOpenAPIHandler("anonymous", openApiConfig, "3.1.0", "yaml"),
];

registerSwaggerUIHandler("anonymous", "api", documents);
