import { getBackendClient } from "./supabase_client.ts";
import { checkConfirmationRateLimit } from "./rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
const MAX_BODY_BYTES = 4096;

function respond(body: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return Response.json(body, { status, headers: { ...corsHeaders, ...extraHeaders } });
}

function validToken(token: unknown): token is string {
  return typeof token === "string" && /^[0-9a-f]{64}$/.test(token);
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond({ error: "Method not allowed." }, 405);
  }

  try {
    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().startsWith("application/json")) {
      return respond({ error: "JSON content required." }, 415);
    }
    // Reject oversized declared payloads early, then enforce actual byte length.
    const declaredSize = request.headers.get("content-length");
    if (declaredSize !== null && Number(declaredSize) > MAX_BODY_BYTES) {
      return respond({ error: "Request too large." }, 413);
    }
    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).length > MAX_BODY_BYTES) {
      return respond({ error: "Request too large." }, 413);
    }
    let body: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(bodyText);
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        return respond({ error: "Invalid request." }, 400);
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return respond({ error: "Invalid JSON." }, 400);
    }

    const { token, confirmed_litres: litres, notes, action } = body;
    if (
  action !== "lookup" &&
  action !== "confirm" &&
  action !== "not_fueled"
) {
      return respond({ error: "Invalid confirmation action." }, 400);
    }
    if (!validToken(token)) {
      return respond({ error: "Invalid or expired confirmation link." }, 400);
    }

    if (action === "confirm") {
      if (typeof litres !== "number" || !Number.isFinite(litres) || litres <= 0 ||
          !Number.isInteger(litres * 100)) {
        return respond({ error: "Enter a valid quantity in litres (up to 2 decimal places)." }, 400);
      }
      if (notes !== undefined && (typeof notes !== "string" || notes.length > 1000)) {
        return respond({ error: "Invalid confirmation notes." }, 400);
      }
    }

if (action === "not_fueled") {
  if (
    notes !== undefined &&
    (typeof notes !== "string" || notes.length > 1000)
  ) {
    return respond(
      { error: "Invalid notes. Maximum 1000 characters." },
      400,
    );
  }
}

    // No verified per-client address source is configured. Do not trust
    // caller-supplied forwarding headers or throttle the whole country together.
    const limit = await checkConfirmationRateLimit(action, token, null);
    if (!limit.allowed) {
      if (limit.status === 429) {
        return respond({ error: "Too many attempts. Please try again shortly." }, 429,
          { "Retry-After": "60" });
      }
      return respond({ error: "Confirmation service temporarily unavailable." }, 503);
    }

const supabase = getBackendClient();

if (action === "not_fueled") {
  const { data, error } = await supabase.rpc(
    "report_fuel_station_not_fueled",
    {
      p_token: token,
      p_notes: notes ?? null,
    },
  );

  if (error) {
    console.error("Not Fueled submission failed:", error.code);
    return respond(
      {
        error:
          "Unable to record Not Fueled. Check that the link is valid and no fuel has already been dispensed.",
      },
      400,
    );
  }

  return respond({
    success: true,
    confirmation_id: data,
    status: "NOT_FUELED",
    message: "Not Fueled recorded. Awaiting MERA review.",
  });
}

if (action === "lookup") {
      const { data, error } = await supabase.rpc(
        "get_fuel_station_confirmation_details", { p_token: token }
      );
      if (error) {
        console.error("Confirmation lookup failed:", error.code);
        return respond({ error: "Unable to retrieve authorization." }, 500);
      }
      if (!data) {
        return respond({ error: "Invalid or expired confirmation link." }, 404);
      }
      return respond({ success: true, authorization: data });
    }

    const { data, error } = await supabase.rpc("confirm_fuel_station_dispensing", {
      p_token: token,
      p_confirmed_litres: litres,
      p_notes: notes ?? null,
    });
    if (error) {
      console.error("Confirmation submission failed:", error.code);
      return respond({ error: "Confirmation rejected. Check the link and approved quantity." }, 400);
    }
    return respond({
      success: true,
      confirmation_id: data,
      message: "Fuel dispensing confirmation recorded successfully.",
    });
  } catch (error) {
    console.error("Fuel confirmation unexpected error:",
      error instanceof Error ? error.message : "unknown error");
    return respond({ error: "Unable to process confirmation request." }, 500);
  }
});
