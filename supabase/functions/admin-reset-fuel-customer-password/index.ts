
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(status: number, data: Record<string, unknown>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return respond(405, { error: "Method not allowed." });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1];

  if (!token) {
    return respond(401, { error: "Authentication required." });
  }

  try {
    const userClient = createClient(
      SUPABASE_URL,
      SUPABASE_ANON_KEY,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const { data: authData, error: authError } =
      await userClient.auth.getUser(token);

    if (authError || !authData.user) {
      return respond(401, { error: "Invalid administrator session." });
    }

    const { data: permitted, error: permissionError } =
      await userClient.rpc("has_fuel_request_permission", {
        p_permission: "APPLICANT_ADMIN",
      });

    if (permissionError || permitted !== true) {
      return respond(403, {
        error: "APPLICANT_ADMIN permission required.",
      });
    }

    let body: Record<string, unknown>;

    try {
      const parsed: unknown = await req.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return respond(400, { error: "Invalid request body." });
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return respond(400, { error: "Invalid JSON payload." });
    }

    const customerId =
      typeof body.customer_id === "string"
        ? body.customer_id.trim()
        : "";

    const newPassword =
      typeof body.new_password === "string"
        ? body.new_password
        : "";

    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        .test(customerId)
    ) {
      return respond(400, { error: "Invalid customer ID." });
    }

    if (newPassword.length < 12 || newPassword.length > 128) {
      return respond(400, {
        error: "Password must contain 12 to 128 characters.",
      });
    }

    const adminClient = createClient(
      SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const { data: customer, error: lookupError } =
      await adminClient
        .from("fuel_applicants")
        .select("auth_user_id")
        .eq("id", customerId)
        .eq("applicant_type", "REGISTERED")
        .single();

    if (lookupError || !customer?.auth_user_id) {
      return respond(404, {
        error: "Registered customer login account not found.",
      });
    }

    const { error: resetError } =
      await adminClient.auth.admin.updateUserById(
        customer.auth_user_id,
        { password: newPassword },
      );

    if (resetError) {
      console.error("Customer password reset failed:", resetError.message);
      return respond(500, {
        error: "Unable to reset customer password.",
      });
    }

    return respond(200, {
      success: true,
      message: "Customer password updated successfully.",
    });
  } catch (error) {
    console.error("Customer password administration error:", error);
    return respond(500, {
      error: "Unable to complete password reset.",
    });
  }
});
