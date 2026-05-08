import type { HttpResponseInit } from "@azure/functions";

const baseHeaders: Record<string, string> = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

export function ok<T>(body: T, headers: Record<string, string> = {}): HttpResponseInit {
  return {
    status: 200,
    headers: { ...baseHeaders, ...headers },
    jsonBody: body,
  };
}

export function fail(
  status: number,
  code: string,
  message: string,
  details?: unknown,
): HttpResponseInit {
  return {
    status,
    headers: baseHeaders,
    jsonBody: { error: { code, message, details } },
  };
}

export const unauthorized = (msg = "Unauthorized") => fail(401, "unauthorized", msg);
export const forbidden = (msg = "Forbidden") => fail(403, "forbidden", msg);
export const badRequest = (msg: string, details?: unknown) =>
  fail(400, "bad_request", msg, details);
export const serverError = (msg = "Internal error", details?: unknown) =>
  fail(500, "server_error", msg, details);
