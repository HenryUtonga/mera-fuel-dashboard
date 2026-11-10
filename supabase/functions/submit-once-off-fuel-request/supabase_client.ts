
import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2";

let backendClient: SupabaseClient | null = null;

export function getBackendClient(): SupabaseClient {
  if (backendClient !== null) {
    return backendClient;
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get(
    "SUPABASE_SERVICE_ROLE_KEY",
  );

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Supabase backend credentials are not configured.",
    );
  }

  backendClient = createClient(
    supabaseUrl,
    serviceRoleKey,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
      global: {
        headers: {
          "X-Client-Info": "mera-fuel-request-backend",
        },
      },
    },
  );

  return backendClient;
}
