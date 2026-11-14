
const GRAPH_BASE = "https://graph.microsoft.com/v1.0";
const SENDER_EMAIL = "permits@mera.mw";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing configuration: ${name}`);
  }
  return value;
}

export async function getAccessToken(): Promise<string> {
  const tenantId = requiredEnv("MS_TENANT_ID");
  const clientId = requiredEnv("MS_CLIENT_ID");
  const clientSecret = requiredEnv("MS_CLIENT_SECRET");

  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    scope: "https://graph.microsoft.com/.default",
    grant_type: "client_credentials",
  });

   const response = await fetch(
    `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
      signal: AbortSignal.timeout(10000),
    },
  );


  console.log(
  "EMAIL DIAGNOSTIC: Microsoft authentication HTTP",
  response.status,
);

  if (!response.ok) {
    throw new Error(
      `Microsoft authentication failed: HTTP ${response.status}`,
    );
  }

  const result = await response.json();
  return result.access_token;
}


export class PermanentEmailError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PermanentEmailError";
  }
}


export class UncertainEmailDeliveryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UncertainEmailDeliveryError";
  }
}
 
export async function sendMicrosoftEmail(
  recipient: string,
  subject: string,
  htmlBody: string,
): Promise<void> {

  const token = await getAccessToken();

  let response: Response;

   try {
    response = await fetch(

      `${GRAPH_BASE}/users/${encodeURIComponent(SENDER_EMAIL)}/sendMail`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            subject,
            body: {
              contentType: "HTML",
              content: htmlBody,
            },
            toRecipients: [
              {
                emailAddress: {
                  address: recipient,
                },
              },
            ],
          },
          saveToSentItems: true,
        }),
        signal: AbortSignal.timeout(15000),
      },
    );
 
   
  } catch {

    // The request may have reached Microsoft before
    // the network connection failed or timed out.
    throw new UncertainEmailDeliveryError(
      "Microsoft Graph submission outcome uncertain.",
    );
  }


if (!response.ok) {
  const message =
    `Microsoft Graph rejected email submission: HTTP ${response.status}`;

  if (
    response.status === 400 ||
    response.status === 401 ||
    response.status === 403 ||
    response.status === 404 ||
    response.status === 422
  ) {
    throw new PermanentEmailError(message);
  }

  throw new Error(message);
}

}

