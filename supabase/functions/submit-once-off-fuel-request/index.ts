
import { validateOnceOffRequest } from "./validation.ts";
import {
  validateDocument,
  type ValidatedDocument,
  type DocumentType,
} from "./documents.ts";
import { getBackendClient } from "./supabase_client.ts";
import {
  uploadRequestDocument,
  type UploadedDocument,
} from "./storage.ts";
import {
  findExistingSubmission,
  submitOnceOffRequest,
} from "./submission.ts";

const MAX_REQUEST_BYTES = 31 * 1024 * 1024;
const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;

const DOCUMENT_FIELDS: Record<string, DocumentType> = {
  identification: "IDENTIFICATION",
  proof_of_need: "PROOF_OF_NEED",
  company_registration: "COMPANY_REGISTRATION",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function respond(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      ...corsHeaders,
      "Cache-Control": "no-store",
    },
  });
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes as BufferSource,
  );

  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function readBoundedRequest(req: Request): Promise<FormData> {
  const declaredLength = req.headers.get("content-length");

  if (declaredLength !== null) {
    const length = Number(declaredLength);

    if (
      !Number.isSafeInteger(length) ||
      length < 0 ||
      length > MAX_REQUEST_BYTES
    ) {
      throw new Error("Request too large.");
    }
  }

  const reader = req.body?.getReader();

  if (!reader) {
    throw new Error("Request body required.");
  }

  const chunks: Uint8Array[] = [];
  let total = 0;

  while (true) {
    const { done, value } = await reader.read();

    if (done) break;

    total += value.byteLength;

    if (total > MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new Error("Request too large.");
    }

    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;

  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  const bounded = new Request(req.url, {
    method: "POST",
    headers: {
      "content-type": req.headers.get("content-type") ?? "",
    },
    body: bytes,
  });

  try {
    return await bounded.formData();
  } catch {
    throw new Error("Invalid multipart form data.");
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Flutter Web browser preflight.
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return respond({
      success: false,
      error: "Method not allowed.",
    }, 405);
  }

  const contentType = req.headers.get("content-type") ?? "";

  if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
    return respond({
      success: false,
      error: "Multipart form data required.",
    }, 415);
  }

  let form: FormData;

  try {
    form = await readBoundedRequest(req);
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Invalid request.";

    return respond({
      success: false,
      error: message,
    }, message === "Request too large." ? 413 : 400);
  }

  try {
    // Validate the submitted form fields.
    const allowedFields = new Set([
      "request",
      "submission_id",
      ...Object.keys(DOCUMENT_FIELDS),
    ]);

    const seen = new Set<string>();

    for (const [field] of form.entries()) {
      if (!allowedFields.has(field) || seen.has(field)) {
        return respond({
          success: false,
          error: "Unexpected or duplicate form field.",
        }, 400);
      }

      seen.add(field);
    }

    // Validate customer information.
    const rawRequest = form.get("request");

    if (
      typeof rawRequest !== "string" ||
      rawRequest.length > 16384
    ) {
      return respond({
        success: false,
        error: "Invalid customer information.",
      }, 400);
    }

    let payload: unknown;

    try {
      payload = JSON.parse(rawRequest);
    } catch {
      return respond({
        success: false,
        error: "Invalid customer JSON.",
      }, 400);
    }

    const validation = validateOnceOffRequest(payload);

    if (!validation.valid || !validation.data) {
      return respond({
        success: false,
        error: validation.error ?? "Invalid request.",
      }, 400);
    }

    // Validate the unique submission identifier.
    const submissionId = form.get("submission_id");

    const uuidPattern =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    if (
      typeof submissionId !== "string" ||
      !uuidPattern.test(submissionId)
    ) {
      return respond({
        success: false,
        error: "Invalid submission ID.",
      }, 400);
    }

    // Validate supporting documents.
    const documents: ValidatedDocument[] = [];

    for (const [field, documentType] of Object.entries(
      DOCUMENT_FIELDS,
    )) {
      const file = form.get(field);

      if (file === null) {
        if (field !== "company_registration") {
          return respond({
            success: false,
            error: `Required document missing: ${field}.`,
          }, 400);
        }

        continue;
      }

      if (
        !(file instanceof File) ||
        file.size > MAX_DOCUMENT_BYTES
      ) {
        return respond({
          success: false,
          error: `Invalid document: ${field}.`,
        }, 400);
      }

      const bytes = new Uint8Array(await file.arrayBuffer());

      const result = validateDocument(
        documentType,
        file.name,
        file.type,
        bytes,
      );

      if (!result.valid || !result.document) {
        return respond({
          success: false,
          error: result.error ?? `Invalid document: ${field}.`,
        }, 400);
      }

      documents.push(result.document);
    }

    // Calculate a fingerprint to identify retries.
    const documentHashes = [];

    for (const document of documents) {
      documentHashes.push({
        type: document.documentType,
        name: document.fileName,
        mime: document.mimeType,
        size: document.size,
        hash: await sha256(document.bytes),
      });
    }

    const fingerprint = await sha256(
      new TextEncoder().encode(
        JSON.stringify({
          request: validation.data,
          documents: documentHashes,
        }),
      ),
    );

    const supabase = getBackendClient();

    // Return the existing reference for a completed retry.
    const existing = await findExistingSubmission(
      supabase,
      submissionId,
      fingerprint,
    );

    if (existing) {
      return respond({
        success: true,
        request_id: existing.requestId,
        request_number: existing.requestNumber,
        already_submitted: true,
      });
    }

    // Acquire submission ownership.
    const { data: reservationData, error: reservationError } =
      await supabase.rpc("acquire_fuel_request_submission", {
        p_submission_id: submissionId,
        p_fingerprint: fingerprint,
      });

    if (reservationError) {
      console.error("Reservation failed:", reservationError.message);

      return respond({
        success: false,
        error: "Unable to reserve submission. Please retry.",
        retryable: true,
      }, 503);
    }

    const reservation = Array.isArray(reservationData)
      ? reservationData[0]
      : null;

    if (!reservation) {
      return respond({
        success: false,
        error: "Invalid reservation response.",
      }, 500);
    }

    if (reservation.reservation_status === "COMPLETED") {
      return respond({
        success: true,
        request_id: reservation.existing_request_id,
        request_number: reservation.existing_request_number,
        already_submitted: true,
      });
    }

    if (reservation.reservation_status === "PROCESSING") {
      return respond({
        success: false,
        error: "Request is already being processed. Retry shortly.",
        retryable: true,
      }, 409);
    }

    if (
      reservation.reservation_status !== "ACQUIRED" ||
      typeof reservation.reservation_token !== "string"
    ) {
      return respond({
        success: false,
        error: "Unable to acquire submission reservation.",
      }, 500);
    }

    const reservationToken: string =
      reservation.reservation_token;

    try {
      // Upload documents to private Supabase Storage.
      const uploaded: UploadedDocument[] = [];

      for (const document of documents) {
        uploaded.push(
          await uploadRequestDocument(
            supabase,
            submissionId,
            document,
          ),
        );
      }

      // Verify reservation ownership before database commit.
      const { data: renewed, error: renewError } =
        await supabase.rpc("renew_fuel_request_submission", {
          p_submission_id: submissionId,
          p_reservation_token: reservationToken,
        });

      if (renewError || renewed !== true) {
        throw new Error("Submission reservation expired.");
      }

      // Save the request, fuel items and document metadata.
      const result = await submitOnceOffRequest(
        supabase,
        validation.data,
        uploaded,
        submissionId,
        fingerprint,
        reservationToken,
      );

      return respond({
        success: true,
        request_id: result.requestId,
        request_number: result.requestNumber,
        already_submitted: false,
      });
    } catch (error) {
      console.error("Submission failed:", error);

      // Check whether the database committed before reporting failure.
      let recoveryConfirmed = false;

      try {
        const recovered = await findExistingSubmission(
          supabase,
          submissionId,
          fingerprint,
        );

        if (recovered) {
          return respond({
            success: true,
            request_id: recovered.requestId,
            request_number: recovered.requestNumber,
            already_submitted: true,
          });
        }

        recoveryConfirmed = true;
      } catch (recoveryError) {
        console.error("Recovery lookup failed:", recoveryError);
      }

      // Release only when we have verified no request was committed.
      if (recoveryConfirmed) {
        const { error: releaseError } = await supabase.rpc(
          "release_fuel_request_submission",
          {
            p_submission_id: submissionId,
            p_reservation_token: reservationToken,
          },
        );

        if (releaseError) {
          console.error("Reservation release failed:", releaseError);
        }
      }

      // Uploaded documents are retained for safe retries.
      return respond({
        success: false,
        error: "Submission could not be confirmed. Please retry.",
        retryable: true,
      }, 503);
    }
  } catch (error) {
    console.error("Once-Off request failed:", error);

    return respond({
      success: false,
      error: "Unable to process request.",
    }, 500);
  }
});
