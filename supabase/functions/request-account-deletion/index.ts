import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};
const json = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8" },
});
const preflight = (request: Request) => request.method === "OPTIONS" ?
  new Response("ok", { headers: corsHeaders }) : null;
function userClient(request: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = request.headers.get("authorization");
  if (!url || !anonKey || !authorization) throw new Error("AUTH_REQUIRED");
  return createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
function publicError(error: unknown): { status: number; code: string } {
  const message = error instanceof Error ? error.message : String(error);
  const known = ["AUTH_REQUIRED", "FORBIDDEN", "OWNER_TRANSFER_REQUIRED", "REAUTHENTICATION_REQUIRED"]
    .find((code) => message.includes(code));
  const unauthorized = known === "AUTH_REQUIRED" || known === "REAUTHENTICATION_REQUIRED";
  const forbidden = known === "FORBIDDEN" || known === "OWNER_TRANSFER_REQUIRED";
  return { status: unauthorized ? 401 : forbidden ? 403 : 400, code: known ?? "BACKEND_UNAVAILABLE" };
}

Deno.serve(async (request) => {
  const options = preflight(request); if (options) return options;
  if (request.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });
  try {
    const body = await request.json() as { confirmation?: string };
    if (body.confirmation !== "DELETE_MY_ACCOUNT") {
      return json(400, { code: "CONFIRMATION_REQUIRED" });
    }
    const client = userClient(request);
    const { data, error } = await client.rpc("request_account_deletion_v1");
    if (error) throw error;
    return json(202, { jobId: data, status: "queued", purgeAfterDays: 30 });
  } catch (error) {
    const safe = publicError(error); return json(safe.status, { code: safe.code });
  }
});
