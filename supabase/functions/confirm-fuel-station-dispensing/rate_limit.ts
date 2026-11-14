import { getBackendClient } from "./supabase_client.ts";

type Action = "lookup" | "confirm" | "not_fueled";
type Result = { allowed: true } | { allowed: false; status: 429 | 503 };

const SOURCE_LIMIT: Record<Action, number> = {
  lookup: 60,
  confirm: 15,
  not_fueled: 15,
};

const TOKEN_LIMIT: Record<Action, number> = {
  lookup: 20,
  confirm: 5,
  not_fueled: 5,
};const WINDOW_SECONDS = 60;
let keyPromise: Promise<CryptoKey> | undefined;

function hmacKey(): Promise<CryptoKey> {
  if (!keyPromise) {
    keyPromise = (async () => {
      const secret = Deno.env.get("FUEL_CONFIRM_RATE_LIMIT_SECRET");
      if (!secret || !/^[a-f0-9]{64}$/i.test(secret)) {
        throw new Error("Rate-limit secret is missing or invalid");
      }
      const bytes = Uint8Array.from(secret.match(/../g)!, (x) => parseInt(x, 16));
      return await crypto.subtle.importKey(
        "raw", bytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
      );
    })();
  }
  return keyPromise;
}

async function identifier(value: string): Promise<string> {
  const signature = await crypto.subtle.sign(
    "HMAC", await hmacKey(), new TextEncoder().encode(value)
  );
  return Array.from(new Uint8Array(signature), (x) => x.toString(16).padStart(2, "0")).join("");
}

async function check(id: string, action: Action, max: number): Promise<boolean> {
  const { data, error } = await getBackendClient().rpc("check_fuel_confirmation_rate_limit", {
    p_identifier: id,
    p_action: action,
    p_max_attempts: max,
    p_window_seconds: WINDOW_SECONDS,
  });
  if (error || typeof data !== "boolean") {
    throw new Error(`Rate-limit RPC failed: ${error?.code ?? "invalid response"}`);
  }
  return data;
}

/**
 * trustedSource must come from a verified edge/gateway identity, NEVER from
 * an arbitrary X-Forwarded-For or other caller-controlled request header.
 * Null deliberately skips source-wide throttling; token throttling remains active.
 */
export async function checkConfirmationRateLimit(
  action: Action,
  token: string,
  trustedSource: string | null = null,
): Promise<Result> {
  try {
    // Token check is always enforced, even when no trusted source is available.
    // Both response actions share one rate-limit bucket.
const limitAction: "lookup" | "confirm" =
  action === "lookup" ? "lookup" : "confirm";

const tokenId = await identifier(`fuel-confirm:v1:token:${token}`);

if (!(await check(tokenId, limitAction, TOKEN_LIMIT[action]))) {
  return { allowed: false, status: 429 };
}

if (trustedSource) {
  const sourceId = await identifier(
    `fuel-confirm:v1:source:${trustedSource}`,
  );

  if (!(await check(sourceId, limitAction, SOURCE_LIMIT[action]))) {
    return { allowed: false, status: 429 };
  }
}
    return { allowed: true };
  } catch (error) {
    console.error("Fuel confirmation rate-limit unavailable:",
      error instanceof Error ? error.message : "unknown error");
    return { allowed: false, status: 503 };
  }
}
