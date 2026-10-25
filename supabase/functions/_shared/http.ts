export const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};

export function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8" },
  });
}

export function preflight(request: Request): Response | null {
  return request.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}

export function publicError(error: unknown): { status: number; code: string } {
  const message = error instanceof Error ? error.message :
    error && typeof error === "object" && "message" in error ?
    String((error as { message: unknown }).message) : String(error);
  const known = [
    "AUTH_REQUIRED", "FORBIDDEN", "INVITE_INVALID", "INVITE_EXPIRED",
    "INVITE_ALREADY_USED", "INVITE_RATE_LIMITED", "MEMBER_ALREADY_ACTIVE",
    "OWNER_TRANSFER_REQUIRED", "REAUTHENTICATION_REQUIRED",
    "VALIDATION_FAILED", "FAMILY_NOT_FOUND",
  ].find((code) => message.includes(code));
  const forbidden = known === "FORBIDDEN" || known === "OWNER_TRANSFER_REQUIRED";
  const unauthorized = known === "AUTH_REQUIRED" || known === "REAUTHENTICATION_REQUIRED";
  return { status: unauthorized ? 401 : forbidden ? 403 : 400, code: known ?? "BACKEND_UNAVAILABLE" };
}
