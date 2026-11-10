
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import type { OnceOffRequest } from "./validation.ts";
import type { UploadedDocument } from "./storage.ts";

export interface SubmissionResult {
  requestId: string;
  requestNumber: string;
}

export async function submitOnceOffRequest(
  supabase: SupabaseClient,
  request: OnceOffRequest,
  documents: UploadedDocument[],
  submissionId: string,
  fingerprint: string,
  reservationToken: string,
): Promise<SubmissionResult> {
  const identification = documents.some(
    (doc) => doc.documentType === "IDENTIFICATION",
  );

  const proofOfNeed = documents.some(
    (doc) => doc.documentType === "PROOF_OF_NEED",
  );

  if (!identification || !proofOfNeed) {
    throw new Error(
      "Identification and Proof of Fuel Need are required.",
    );
  }

  if (documents.length < 2 || documents.length > 3) {
    throw new Error("Invalid document collection.");
  }

  const documentTypes = documents.map(
    (doc) => doc.documentType,
  );

  if (new Set(documentTypes).size !== documentTypes.length) {
    throw new Error("Duplicate document types.");
  }

  const documentMetadata = documents.map((doc) => ({
    document_type: doc.documentType,
    file_name: doc.fileName,
    storage_path: doc.storagePath,
    mime_type: doc.mimeType,
    file_size_bytes: doc.size,
  }));

 const { data, error } = await supabase.rpc(
  "submit_once_off_fuel_request_idempotent",
  {
      p_applicant_name: request.applicant_name,
      p_email: request.email,
      p_phone_number: request.phone_number,
      p_district_id: request.district_id,
      p_omc_id: request.omc_id,
      p_station_id: request.station_id,
      p_reason: request.reason,
      p_items: request.items,
      p_documents: documentMetadata,
      p_submission_id: submissionId,
p_submission_fingerprint: fingerprint,
p_reservation_token: reservationToken,
    },
  );

  if (error) {
    console.error("Fuel request database submission failed:", {
      code: error.code,
      message: error.message,
    });

    throw new Error("Unable to submit the fuel request.");
  }

  if (!Array.isArray(data) || data.length !== 1) {
    throw new Error(
      "Unexpected database submission response.",
    );
  }

  const result = data[0];

  if (
    typeof result.request_id !== "string" ||
    typeof result.request_number !== "string"
  ) {
    throw new Error(
      "Invalid request confirmation received.",
    );
  }

  return {
    requestId: result.request_id,
    requestNumber: result.request_number,
  };
}

export async function findExistingSubmission(
  supabase: SupabaseClient,
  submissionId: string,
  fingerprint: string,
): Promise<SubmissionResult | null> {
  const { data, error } = await supabase
    .from("fuel_requests")
    .select("id, request_number, submission_fingerprint")
    .eq("submission_id", submissionId)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to check existing submission: ${error.message}`,
    );
  }

  if (!data) {
    return null;
  }

  if (data.submission_fingerprint !== fingerprint) {
    throw new Error(
      "Submission identifier already used with different information.",
    );
  }

  return {
    requestId: data.id,
    requestNumber: data.request_number,
  };
}
