
export type DocumentType =
  | "IDENTIFICATION"
  | "PROOF_OF_NEED"
  | "COMPANY_REGISTRATION";

export interface ValidatedDocument {
  documentType: DocumentType;
  fileName: string;
  mimeType: string;
  size: number;
  bytes: Uint8Array;
}

export interface DocumentValidationResult {
  valid: boolean;
  error?: string;
  document?: ValidatedDocument;
}

const MAX_FILE_SIZE = 10 * 1024 * 1024;

const allowedMimeTypes = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const allowedDocumentTypes = new Set<DocumentType>([
  "IDENTIFICATION",
  "PROOF_OF_NEED",
  "COMPANY_REGISTRATION",
]);

function startsWith(
  bytes: Uint8Array,
  signature: number[],
): boolean {
  return signature.every(
    (value, index) => bytes[index] === value,
  );
}

function detectMimeType(
  bytes: Uint8Array,
): string | null {
  // PDF: %PDF-
  if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d])) {
    return "application/pdf";
  }

  // JPEG
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) {
    return "image/jpeg";
  }

  // PNG
  if (
    startsWith(
      bytes,
      [137, 80, 78, 71, 13, 10, 26, 10],
    )
  ) {
    return "image/png";
  }

  // WebP: RIFF....WEBP
  if (
    bytes.length >= 12 &&
    startsWith(bytes, [82, 73, 70, 70]) &&
    startsWith(
      bytes.subarray(8),
      [87, 69, 66, 80],
    )
  ) {
    return "image/webp";
  }

  return null;
}

export function validateDocument(
  documentType: string,
  fileName: string,
  declaredMimeType: string,
  bytes: Uint8Array,
): DocumentValidationResult {
  if (
    !allowedDocumentTypes.has(
      documentType as DocumentType,
    )
  ) {
    return {
      valid: false,
      error: "Unsupported document type.",
    };
  }

  if (
    typeof fileName !== "string" ||
    fileName.trim().length === 0 ||
    fileName.length > 255
  ) {
    return {
      valid: false,
      error: "Invalid document filename.",
    };
  }

  if (
    !(bytes instanceof Uint8Array) ||
    bytes.length === 0 ||
    bytes.length > MAX_FILE_SIZE
  ) {
    return {
      valid: false,
      error: "Document must not exceed 10 MB.",
    };
  }

  const detectedMimeType = detectMimeType(bytes);

  if (
    !detectedMimeType ||
    !allowedMimeTypes.has(detectedMimeType)
  ) {
    return {
      valid: false,
      error: "Unsupported document format.",
    };
  }

  if (
    declaredMimeType &&
    declaredMimeType.toLowerCase() !== detectedMimeType
  ) {
    return {
      valid: false,
      error: "Document format does not match its content.",
    };
  }

  return {
    valid: true,
    document: {
      documentType: documentType as DocumentType,
      fileName: fileName.trim(),
      mimeType: detectedMimeType,
      size: bytes.length,
      bytes,
    },
  };
}
