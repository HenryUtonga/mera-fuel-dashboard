
export interface OnceOffRequest {
  applicant_name: string;
  email: string;
  phone_number: string;
  district_id: string;
  omc_id: string;
  station_id: string;
  reason: string;
  items: {
    product: "PETROL" | "DIESEL";
    litres: number;
  }[];
}

export interface ValidationResult {
  valid: boolean;
  error?: string;
  data?: OnceOffRequest;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const isObject = (
  value: unknown,
): value is Record<string, unknown> =>
  value !== null &&
  typeof value === "object" &&
  !Array.isArray(value);

const isValidUuid = (value: unknown): value is string =>
  typeof value === "string" && uuidPattern.test(value);

export function validateOnceOffRequest(
  payload: unknown,
): ValidationResult {
  if (!isObject(payload)) {
    return {
      valid: false,
      error: "Invalid request payload.",
    };
  }

  const name = typeof payload.applicant_name === "string"
    ? payload.applicant_name.trim()
    : "";

  const email = typeof payload.email === "string"
    ? payload.email.trim().toLowerCase()
    : "";

  const phone = typeof payload.phone_number === "string"
    ? payload.phone_number.trim()
    : "";

  const reason = typeof payload.reason === "string"
    ? payload.reason.trim()
    : "";

  if (name.length < 3 || name.length > 200) {
    return {
      valid: false,
      error: "Customer name must contain 3–200 characters.",
    };
  }

  if (
    email.length > 254 ||
    !emailPattern.test(email)
  ) {
    return {
      valid: false,
      error: "Enter a valid email address.",
    };
  }

  if (phone.length < 7 || phone.length > 30) {
    return {
      valid: false,
      error: "Enter a valid phone number.",
    };
  }

  if (reason.length < 10 || reason.length > 2000) {
    return {
      valid: false,
      error: "Reason must contain 10–2000 characters.",
    };
  }

  if (
    !isValidUuid(payload.district_id) ||
    !isValidUuid(payload.omc_id) ||
    !isValidUuid(payload.station_id)
  ) {
    return {
      valid: false,
      error: "Invalid district, OMC or filling station.",
    };
  }

  if (
    !Array.isArray(payload.items) ||
    payload.items.length < 1 ||
    payload.items.length > 2
  ) {
    return {
      valid: false,
      error: "Select Petrol, Diesel or both.",
    };
  }

  const seenProducts = new Set<string>();

  const items: OnceOffRequest["items"] = [];

  for (const item of payload.items) {
    if (!isObject(item)) {
      return {
        valid: false,
        error: "Invalid fuel item.",
      };
    }

    const product = item.product;

    if (product !== "PETROL" && product !== "DIESEL") {
      return {
        valid: false,
        error: "Only Petrol and Diesel are supported.",
      };
    }

    if (seenProducts.has(product)) {
      return {
        valid: false,
        error: "Duplicate fuel products are not allowed.",
      };
    }

    seenProducts.add(product);

    const litres = item.litres;

    if (
      typeof litres !== "number" ||
      !Number.isFinite(litres) ||
      litres <= 0 ||
      litres > 999999999999.99 ||
      Math.round(litres * 100) / 100 !== litres
    ) {
      return {
        valid: false,
        error: "Fuel quantity must be positive with at most two decimal places.",
      };
    }

    items.push({ product, litres });
  }

  return {
    valid: true,
    data: {
      applicant_name: name,
      email,
      phone_number: phone,
      district_id: payload.district_id,
      omc_id: payload.omc_id,
      station_id: payload.station_id,
      reason,
      items,
    },
  };
}
