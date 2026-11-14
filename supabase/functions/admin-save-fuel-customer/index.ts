
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

function respond(
  status: number,
  data: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function requiredText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function optionalText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validDate(value: unknown): boolean {
  if (typeof value !== "string") return false;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return respond(405, { error: "Method not allowed." });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1];

  if (!token) {
    return respond(401, { error: "Authentication required." });
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

  let createdAuthUserId: string | null = null;

  try {
    // Verify the token with Supabase Auth.
    const { data: authData, error: authError } =
      await userClient.auth.getUser(token);

    if (authError || !authData.user) {
      return respond(401, {
        error: "Invalid or expired administrator session.",
      });
    }

    const adminUserId = authData.user.id;

    // Check the permission using the verified user's JWT.
    const { data: permitted, error: permissionError } =
      await userClient.rpc("has_fuel_request_permission", {
        p_permission: "APPLICANT_ADMIN",
      });

    if (permissionError || permitted !== true) {
      return respond(403, {
        error: "APPLICANT_ADMIN permission required.",
      });
    }

    let payload: Record<string, unknown>;

    try {
      const body = await req.json();

      if (
        !body ||
        typeof body !== "object" ||
        Array.isArray(body)
      ) {
        return respond(400, { error: "Invalid request body." });
      }

      payload = body;
    } catch {
      return respond(400, { error: "Invalid JSON payload." });
    }

    const applicantName = requiredText(payload.applicant_name);
    const email = requiredText(payload.email).toLowerCase();
    const phone = requiredText(payload.phone_number);
    const category = requiredText(payload.allowance_category);
    const status = requiredText(payload.account_status);
    const validFrom = payload.valid_from;
    const expiresOn = payload.expires_on;
    const allowances = payload.allowances;
    const existingId = requiredText(payload.id);

    if (!applicantName || !phone) {
      return respond(400, {
        error: "Customer name and phone number are required.",
      });
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return respond(400, { error: "Invalid customer email." });
    }

    if (!["TYPE_A", "TYPE_B"].includes(category)) {
      return respond(400, { error: "Invalid allowance category." });
    }

    if (!["ACTIVE", "SUSPENDED", "EXPIRED"].includes(status)) {
      return respond(400, { error: "Invalid account status." });
    }

    if (
      !validDate(validFrom) ||
      !validDate(expiresOn) ||
      String(expiresOn) < String(validFrom)
    ) {
      return respond(400, { error: "Invalid validity dates." });
    }

    if (typeof payload.auto_approval_enabled !== "boolean") {
      return respond(400, {
        error: "Auto approval must be true or false.",
      });
    }

    if (!Array.isArray(allowances) || allowances.length > 3) {
      return respond(400, { error: "Invalid fuel allowances." });
    }

    const products = new Set<string>();

    for (const item of allowances) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        return respond(400, { error: "Invalid allowance entry." });
      }

      const product = requiredText(item.product);
      const allowanceType = requiredText(item.allowance_type);
      const quantity = item.limit_litres;

      if (
        !["PETROL", "DIESEL", "KEROSENE"].includes(product) ||
        products.has(product)
      ) {
        return respond(400, {
          error: "Invalid or duplicate fuel product.",
        });
      }

      products.add(product);

      const validType = category === "TYPE_B"
        ? allowanceType === "PER_SESSION"
        : ["DAILY", "WEEKLY", "MONTHLY"].includes(allowanceType);

      if (!validType) {
        return respond(400, {
          error: `Invalid allowance type for ${product}.`,
        });
      }

      if (
        typeof quantity !== "number" ||
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        quantity > 999999999999.99 ||
        !Number.isInteger(Math.round(quantity * 100)) ||
        Math.abs(
          quantity * 100 - Math.round(quantity * 100)
        ) > 0.00001
      ) {
        return respond(400, {
          error: `Invalid allowance quantity for ${product}.`,
        });
      }
    }

    const customerPayload: Record<string, unknown> = {
      applicant_name: applicantName,
      company_name: optionalText(payload.company_name),
      email,
      phone_number: phone,
      registration_number: optionalText(payload.registration_number),
      account_status: status,
      auto_approval_enabled: payload.auto_approval_enabled,
      valid_from: validFrom,
      expires_on: expiresOn,
      allowance_category: category,
      allowances,
    };

    if (existingId) {
      // Existing customers retain their Auth identity.
      customerPayload.id = existingId;
    } else {
      // Prevent accidental duplicate customer registration.
      const { data: existingCustomer, error: lookupError } =
        await adminClient
          .from("fuel_applicants")
          .select("id")
          .eq("email", email)
          .limit(1);

      if (lookupError) throw lookupError;

      if (existingCustomer && existingCustomer.length > 0) {
        return respond(409, {
          error: "A registered customer already uses this email.",
        });
      }

      // Supabase sends the customer an account invitation.
      const { data: invitation, error: inviteError } =
        await adminClient.auth.admin.inviteUserByEmail(email);

      if (inviteError || !invitation.user) {
        return respond(400, {
          error: inviteError?.message ??
            "Unable to create customer invitation.",
        });
      }

      createdAuthUserId = invitation.user.id;
      customerPayload.auth_user_id = createdAuthUserId;
    }

    // One PostgreSQL transaction saves customer and allowances.
    const { data: customerId, error: saveError } =
      await adminClient.rpc("admin_save_fuel_customer", {
        p_customer: customerPayload,
        p_admin_user_id: adminUserId,
      });

    if (saveError) {
      // Best-effort cleanup of a newly invited Auth account.
      // Never delete an existing customer's Auth account.
      if (createdAuthUserId) {
        const { error: cleanupError } =
          await adminClient.auth.admin.deleteUser(
            createdAuthUserId,
          );

        if (cleanupError) {
          console.error(
            "Auth cleanup failed:",
            createdAuthUserId,
            cleanupError.message,
          );
        }
      }

      console.error("Customer save failed:", saveError.message);

      return respond(400, {
        error: saveError.message,
      });
    }

    return respond(200, {
      success: true,
      customer_id: customerId,
      action: existingId ? "UPDATED" : "CREATED",
      invitation_sent: !existingId,
      message: existingId
        ? "Customer updated successfully."
        : "Customer created and invitation initiated.",
    });
  } catch (error) {
    console.error("Customer administration error:", error);

    return respond(500, {
      error: "Unable to complete customer administration request.",
    });
  }
});
