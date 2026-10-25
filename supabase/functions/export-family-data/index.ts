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
  const known = ["AUTH_REQUIRED", "FORBIDDEN", "VALIDATION_FAILED"].find((code) => message.includes(code));
  return { status: known === "AUTH_REQUIRED" ? 401 : known === "FORBIDDEN" ? 403 : 400, code: known ?? "BACKEND_UNAVAILABLE" };
}

const maxExportBytes = 10 * 1024 * 1024;

function csvCell(value: unknown): string {
  let raw = value === null || value === undefined ? "" :
    typeof value === "object" ? JSON.stringify(value) : String(value);
  // Prevent spreadsheet formula execution when a user opens the export.
  if (/^[=+\-@]/.test(raw)) raw = `'${raw}`;
  return `"${raw.replaceAll('"', '""')}"`;
}

function csvDocument(data: Record<string, unknown>): string {
  const lines: string[] = [];
  for (const [section, value] of Object.entries(data)) {
    const rows = Array.isArray(value) ? value : value && typeof value === "object" ? [value] : [];
    if (!rows.length) continue;
    const keys = [...new Set(rows.flatMap((row) => Object.keys(row as Record<string, unknown>)))];
    lines.push(`# ${section}`, keys.map(csvCell).join(","));
    for (const row of rows as Record<string, unknown>[]) {
      lines.push(keys.map((key) => csvCell(row[key])).join(","));
    }
    lines.push("");
  }
  return `\uFEFF${lines.join("\r\n")}`;
}

Deno.serve(async (request) => {
  const options = preflight(request); if (options) return options;
  if (request.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });
  try {
    const body = await request.json() as { familyId?: string; format?: "json_v1" | "csv_v1" };
    const format = body.format ?? "json_v1";
    if (!body.familyId || !["json_v1", "csv_v1"].includes(format)) {
      return json(400, { code: "VALIDATION_FAILED" });
    }
    const client = userClient(request);
    const { data, error } = await client.rpc("export_family_data_v1", {
      p_family_id: body.familyId, p_format: format,
    });
    if (error) throw error;
    const envelope = data as { jobId: string; data: Record<string, unknown> };
    const content = format === "csv_v1" ? csvDocument(envelope.data) :
      JSON.stringify({ jobId: envelope.jobId, data: envelope.data });
    if (new TextEncoder().encode(content).byteLength > maxExportBytes) {
      return json(413, { code: "EXPORT_TOO_LARGE" });
    }
    return new Response(content, {
      status: 200,
      headers: {
        ...corsHeaders,
        "content-type": format === "csv_v1" ? "text/csv; charset=utf-8" : "application/json; charset=utf-8",
        "content-disposition": `attachment; filename="family-memory.${format === "csv_v1" ? "csv" : "json"}"`,
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      },
    });
  } catch (error) {
    const safe = publicError(error); return json(safe.status, { code: safe.code });
  }
});
