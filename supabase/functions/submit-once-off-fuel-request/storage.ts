
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { ValidatedDocument } from "./documents.ts";

const BUCKET = "fuel-request-documents";

export interface UploadedDocument {
  documentType: ValidatedDocument["documentType"];
  fileName: string;
  mimeType: string;
  size: number;
  storageBucket: string;
  storagePath: string;
}

const EXTENSIONS: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

async function fileHash(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes as BufferSource,
  );

  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function uploadRequestDocument(
  supabase: SupabaseClient,
  submissionId: string,
  document: ValidatedDocument,
): Promise<UploadedDocument> {
  const extension = EXTENSIONS[document.mimeType];

  if (!extension) {
    throw new Error("Unsupported document format.");
  }

  const hash = await fileHash(document.bytes);

  const storagePath =
    `once-off/${submissionId}/${document.documentType}-${hash}.${extension}`;

  const storage = supabase.storage.from(BUCKET);

  const { error } = await storage.upload(
    storagePath,
    document.bytes,
    {
      contentType: document.mimeType,
      upsert: false,
    },
  );

  if (error) {
    // A retry may encounter a document uploaded previously.
    // Only reuse it after verifying the actual file contents.
    const { data, error: downloadError } =
      await storage.download(storagePath);

    if (downloadError || !data) {
      console.error("Storage upload failed:", error.message);
      throw new Error("Unable to upload document.");
    }

    const existingHash = await fileHash(
      new Uint8Array(await data.arrayBuffer()),
    );

    if (existingHash !== hash) {
      throw new Error("Stored document does not match upload.");
    }
  }

  return {
    documentType: document.documentType,
    fileName: document.fileName,
    mimeType: document.mimeType,
    size: document.size,
    storageBucket: BUCKET,
    storagePath,
  };
}
