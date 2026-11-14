import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import { stationOwnerEmail } from "./station_email_template.ts";

import { getBackendClient } from "./supabase_client.ts";

import {
  sendMicrosoftEmail,
  UncertainEmailDeliveryError,
  PermanentEmailError,
} from "./microsoft_graph.ts";

import {
  approvalEmail,
  rejectionEmail,
  omcApprovalEmail,
  type FuelAllocation,
  type FuelRequest,
} from "./email_templates.ts";

type QueueItem = {
  id: string;
  request_id: string;
  notification_type: "APPROVED" | "REJECTED";
  recipient_email: string;
  processing_token: string;
};

type OmcQueueItem = {
  id: string;
  request_id: string;
  omc_id: string;
  contact_id: string;
  recipient_email: string;
  processing_token: string;
};

type ApproverQueueItem = {
  id: string;
  request_id: string;
  approver_id: string;
  recipient_email: string;
  processing_token: string;
};

type StationQueueItem = {
  id: string;
  allocation_id: string;
  recipient_email: string;
  confirmation_id: string | null;
  processing_token: string;
};

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (character) => {
    const replacements: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    };
    return replacements[character];
  });
}

async function prepareApproverEmail(item: ApproverQueueItem) {
  const db = getBackendClient();

  const { data: request, error } = await db
    .from("fuel_requests")
    .select("request_number,applicant_name,company_name,status")
    .eq("id", item.request_id)
    .single();

  if (error || !request) {
    throw new Error("Unable to load fuel request for approver.");
  }

  if (request.status !== "PENDING_MERA_APPROVAL") {
    throw new PermanentEmailError(
      "Fuel request is no longer pending MERA approval.",
    );
  }

  const reference = escapeHtml(request.request_number);
  const applicant = escapeHtml(request.applicant_name);
  const company = escapeHtml(request.company_name);

  return {
    subject: `MERA Fuel Request Awaiting Approval - ${request.request_number}`,
    html: `
      <p>A fuel request is awaiting MERA approval.</p>
      <p><strong>Request:</strong> ${reference}</p>
      <p><strong>Applicant:</strong> ${applicant}</p>
      <p><strong>Company:</strong> ${company}</p>
      <p>Please sign in to the MERA Fuel Control dashboard to review
      the request. Do not reply to this automated notification.</p>
    `,
  };
}

type RequestItem = {
  id: string;
  product: string;
};

type AllocationRow = {
  request_item_id: string;
  allocated_litres: number;
  filling_station_id: string;
};

async function prepareEmail(item: QueueItem) {
  const db = getBackendClient();

  const { data: request, error: requestError } = await db
    .from("fuel_requests")
    .select("request_number,applicant_name,company_name,review_notes,status")
    .eq("id", item.request_id)
    .single();

  if (requestError || !request) {
    throw new Error("Unable to load fuel request.");
  }

  if (request.status !== item.notification_type) {
    throw new Error("Fuel request status does not match notification.");
  }

  const details: FuelRequest = {
    request_number: request.request_number,
    applicant_name: request.applicant_name,
    company_name: request.company_name,
    review_notes: request.review_notes,
  };

  if (item.notification_type === "REJECTED") {
    return rejectionEmail(details);
  }

  const { data: requestItems, error: itemsError } = await db
    .from("fuel_request_items")
    .select("id,product")
    .eq("request_id", item.request_id);

  if (itemsError || !requestItems?.length) {
    throw new Error("Approved request items could not be loaded.");
  }

  const typedItems = requestItems as RequestItem[];

  const { data: allocations, error: allocationsError } = await db
    .from("fuel_request_allocations")
    .select("request_item_id,allocated_litres,filling_station_id")
    .in(
      "request_item_id",
      typedItems.map((row) => row.id),
    );

  if (allocationsError || !allocations?.length) {
    throw new Error("Approved station allocations could not be loaded.");
  }

  const typedAllocations = allocations as AllocationRow[];

  const stationIds = [
    ...new Set(typedAllocations.map((row) => row.filling_station_id)),
  ];

  const { data: stations, error: stationsError } = await db
    .from("filling_stations")
    .select("id,name,omc")
    .in("id", stationIds);

  if (stationsError || !stations) {
    throw new Error("Filling station details could not be loaded.");
  }

  const itemMap = new Map(typedItems.map((row) => [row.id, row]));
  const stationMap = new Map(stations.map((row) => [row.id, row]));

  const fuelAllocations: FuelAllocation[] = typedAllocations.map(
    (allocation) => {
      const requestItem = itemMap.get(allocation.request_item_id);
      const station = stationMap.get(allocation.filling_station_id);

      if (!requestItem || !station) {
        throw new Error("Incomplete fuel allocation information.");
      }

      return {
        product: requestItem.product,
        station_name: station.name,
        omc: station.omc,
        litres: Number(allocation.allocated_litres),
      };
    },
  );

  return approvalEmail(details, fuelAllocations);
}

async function prepareOmcEmail(item: OmcQueueItem) {
  const db = getBackendClient();

  const { data: request, error: requestError } = await db
    .from("fuel_requests")
    .select("request_number,applicant_name,company_name,review_notes,status")
    .eq("id", item.request_id)
    .single();

  if (requestError || !request || request.status !== "APPROVED") {
    throw new Error("Approved fuel request could not be loaded.");
  }

  const { data: omc, error: omcError } = await db
    .from("omcs")
    .select("id,name")
    .eq("id", item.omc_id)
    .single();

  if (omcError || !omc) {
    throw new Error("OMC details could not be loaded.");
  }

  const { data: requestItems, error: itemsError } = await db
    .from("fuel_request_items")
    .select("id,product")
    .eq("request_id", item.request_id);

  if (itemsError || !requestItems?.length) {
    throw new Error("Fuel request items could not be loaded.");
  }

  const typedItems = requestItems as RequestItem[];

  const { data: allocations, error: allocationsError } = await db
    .from("fuel_request_allocations")
    .select("request_item_id,allocated_litres,filling_station_id")
    .in(
      "request_item_id",
      typedItems.map((row) => row.id),
    );

  if (allocationsError || !allocations?.length) {
    throw new Error("Fuel allocations could not be loaded.");
  }

  const typedAllocations = allocations as AllocationRow[];

  const stationIds = [
    ...new Set(typedAllocations.map((row) => row.filling_station_id)),
  ];

  const { data: stations, error: stationsError } = await db
    .from("filling_stations")
    .select("id,name,omc_id")
    .in("id", stationIds)
    .eq("omc_id", item.omc_id);

  if (stationsError || !stations?.length) {
    throw new Error("No allocations found for this OMC.");
  }

  const stationMap = new Map(stations.map((row) => [row.id, row]));
  const itemMap = new Map(typedItems.map((row) => [row.id, row]));

  const fuelAllocations: FuelAllocation[] = typedAllocations
    .filter((allocation) => stationMap.has(allocation.filling_station_id))
    .map((allocation) => {
      const requestItem = itemMap.get(allocation.request_item_id);
      const station = stationMap.get(allocation.filling_station_id);

      if (!requestItem || !station) {
        throw new Error("Incomplete OMC allocation information.");
      }

      return {
        product: requestItem.product,
        station_name: station.name,
        omc: omc.name,
        litres: Number(allocation.allocated_litres),
      };
    });

  if (!fuelAllocations.length) {
    throw new Error("No eligible allocations for this OMC.");
  }

  const details: FuelRequest = {
    request_number: request.request_number,
    applicant_name: request.applicant_name,
    company_name: request.company_name,
    review_notes: request.review_notes,
  };

  return omcApprovalEmail(details, omc.name, fuelAllocations);
}

async function processQueueItem(item: QueueItem) {
  const db = getBackendClient();

  let success = false;
  let errorMessage: string | null = null;

  try {
    const email = await prepareEmail(item);

    await sendMicrosoftEmail(item.recipient_email, email.subject, email.html);

    success = true;
  } catch (error) {
    if (error instanceof PermanentEmailError) {
      const { data, error: failError } = await db.rpc(
        "fail_permanent_fuel_request_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );

      if (failError || data !== true) {
        console.error("Unable to record permanent email failure:", item.id);
      }

      return false;
    }

    if (error instanceof UncertainEmailDeliveryError) {
      const { data, error: holdError } = await db.rpc(
        "hold_uncertain_fuel_request_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );

      if (holdError || data !== true) {
        console.error("Unable to hold uncertain email:", item.id);
      }

      return false;
    }

    errorMessage =
      error instanceof Error ? error.message : "Unknown email processing error";
  }

  const { data, error } = await db.rpc("complete_fuel_request_email", {
    p_email_id: item.id,
    p_processing_token: item.processing_token,
    p_success: success,
    p_error: errorMessage,
  });

  if (error || data !== true) {
    console.error("Unable to finalize email queue item:", item.id);
    return false;
  }

  return success;
}

async function processOmcQueueItem(item: OmcQueueItem): Promise<boolean> {
  const db = getBackendClient();

  let success = false;
  let errorMessage: string | null = null;

  try {
    const email = await prepareOmcEmail(item);

    await sendMicrosoftEmail(item.recipient_email, email.subject, email.html);

    success = true;
  } catch (error) {
    if (error instanceof PermanentEmailError) {
      const { data, error: failError } = await db.rpc(
        "fail_permanent_fuel_request_omc_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );

      if (failError || data !== true) {
        console.error("Unable to record permanent OMC email failure:", item.id);
      }

      return false;
    }

    if (error instanceof UncertainEmailDeliveryError) {
      const { data, error: holdError } = await db.rpc(
        "hold_uncertain_fuel_request_omc_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );

      if (holdError || data !== true) {
        console.error("Unable to hold uncertain OMC email:", item.id);
      }

      return false;
    }

    errorMessage =
      error instanceof Error
        ? error.message
        : "Unknown OMC email processing error";
  }

  const { data, error } = await db.rpc("complete_fuel_request_omc_email", {
    p_email_id: item.id,
    p_processing_token: item.processing_token,
    p_success: success,
    p_error: errorMessage,
  });

  if (error || data !== true) {
    console.error("Unable to finalize OMC email queue item:", item.id);
    return false;
  }

  return success;
}

async function processApproverQueueItem(
  item: ApproverQueueItem,
): Promise<boolean> {
  const db = getBackendClient();
  let success = false;
  let errorMessage: string | null = null;

  try {
    const email = await prepareApproverEmail(item);
    await sendMicrosoftEmail(item.recipient_email, email.subject, email.html);
    success = true;
  } catch (error) {
    if (error instanceof PermanentEmailError) {
      const { data, error: failError } = await db.rpc(
        "fail_permanent_fuel_request_approver_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );
      if (failError || data !== true) {
        console.error(
          "Unable to record permanent approver email failure:",
          item.id,
        );
      }
      return false;
    }

    if (error instanceof UncertainEmailDeliveryError) {
      const { data, error: holdError } = await db.rpc(
        "hold_uncertain_fuel_request_approver_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );
      if (holdError || data !== true) {
        console.error("Unable to hold uncertain approver email:", item.id);
      }
      return false;
    }

    errorMessage =
      error instanceof Error
        ? error.message
        : "Unknown approver email processing error";
  }

  const { data, error } = await db.rpc("complete_fuel_request_approver_email", {
    p_email_id: item.id,
    p_processing_token: item.processing_token,
    p_success: success,
    p_error: errorMessage,
  });

  if (error || data !== true) {
    console.error("Unable to finalize approver email queue item:", item.id);
    return false;
  }
  return success;
}

const STATION_CONFIRMATION_URL =
  "https://henryutonga.github.io/mera-fuel-dashboard/#/station-confirmation";

async function processStationQueueItem(
  item: StationQueueItem,
): Promise<boolean> {
  const db = getBackendClient();
  let success = false;
  let errorMessage: string | null = null;

  try {
    // Prepare or reuse the secure confirmation.
    const { data: confirmationId, error: prepareError } = await db.rpc(
      "prepare_fuel_request_station_email",
      {
        p_queue_id: item.id,
        p_processing_token: item.processing_token,
      },
    );

    if (prepareError || !confirmationId) {
      throw new Error("Unable to prepare station confirmation.");
    }

    // Retrieve token only for this claimed queue item.
    const { data: token, error: tokenError } = await db.rpc(
      "get_claimed_fuel_station_email_token",
      {
        p_queue_id: item.id,
        p_processing_token: item.processing_token,
      },
    );

    if (
      tokenError ||
      typeof token !== "string" ||
      !/^[0-9a-f]{64}$/.test(token)
    ) {
      throw new PermanentEmailError(
        "Station confirmation token unavailable or expired.",
      );
    }

    // Retrieve authorization details using the secure token.
    const { data: authorization, error: detailsError } = await db.rpc(
      "get_fuel_station_confirmation_details",
      {
        p_token: token,
      },
    );

    if (detailsError || !authorization) {
      throw new PermanentEmailError(
        "Station authorization unavailable or no longer valid.",
      );
    }

    const details = authorization as Record<string, unknown>;

    const confirmUrl = `${STATION_CONFIRMATION_URL}?token=${token}&action=confirm`;

    const notFueledUrl = `${STATION_CONFIRMATION_URL}?token=${token}&action=not_fueled`;

    const email = stationOwnerEmail({
      requestNumber: String(details.request_number ?? ""),
      applicantName: String(details.applicant_name ?? ""),
      stationName: String(details.station_name ?? ""),
      omc: String(details.omc ?? ""),
      product: String(details.product ?? ""),
      allocatedLitres: Number(details.allocated_litres ?? 0),
      expiresAt: String(details.expires_at ?? ""),
      confirmUrl,
      notFueledUrl,
    });

    await sendMicrosoftEmail(item.recipient_email, email.subject, email.html);

    success = true;
  } catch (error) {
    if (error instanceof PermanentEmailError) {
      const { data, error: failError } = await db.rpc(
        "fail_permanent_fuel_request_station_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );

      if (failError || data !== true) {
        console.error(
          "Unable to record permanent station email failure:",
          item.id,
        );
      }
      return false;
    }

    if (error instanceof UncertainEmailDeliveryError) {
      const { data, error: holdError } = await db.rpc(
        "hold_uncertain_fuel_request_station_email",
        {
          p_email_id: item.id,
          p_processing_token: item.processing_token,
          p_error: error.message,
        },
      );

      if (holdError || data !== true) {
        console.error("Unable to hold uncertain station email:", item.id);
      }
      return false;
    }

    errorMessage =
      error instanceof Error
        ? error.message
        : "Unknown station email processing error";
  }

  const { data, error } = await db.rpc("complete_fuel_request_station_email", {
    p_email_id: item.id,
    p_processing_token: item.processing_token,
    p_success: success,
    p_error: errorMessage,
  });

  if (error || data !== true) {
    console.error("Unable to finalize station email queue item:", item.id);
    return false;
  }

  return success;
}

export default {
  fetch: withSupabase(
    { auth: ["secret:mera_fuel_email_worker"] },
    async (req, _ctx) => {
      const db = getBackendClient();

      const { data: queue, error } = await db.rpc("claim_fuel_request_emails", {
        p_batch_size: 10,
      });

      if (error) {
        console.error("Unable to claim fuel request emails.");
        return Response.json(
          { success: false, error: "Queue unavailable" },
          { status: 500 },
        );
      }

      let sent = 0;
      let failed = 0;

      for (const item of (queue ?? []) as QueueItem[]) {
        const result = await processQueueItem(item);

        if (result) {
          sent++;
        } else {
          failed++;
        }
      }

      // Process OMC notifications separately from customer emails.
      const { data: omcQueue, error: omcQueueError } = await db.rpc(
        "claim_fuel_request_omc_emails",
        { p_batch_size: 10 },
      );

      let omcSent = 0;
      let omcFailed = 0;

      if (omcQueueError) {
        console.error(
          "Unable to claim OMC notification emails:",
          omcQueueError.message,
        );
      } else {
        for (const item of (omcQueue ?? []) as OmcQueueItem[]) {
          const result = await processOmcQueueItem(item);

          if (result) {
            omcSent++;
          } else {
            omcFailed++;
          }
        }
      }

      // Process MERA regional approver notifications.
      const { data: approverQueue, error: approverQueueError } = await db.rpc(
        "claim_fuel_request_approver_emails",
        { p_batch_size: 10 },
      );

      let approverSent = 0;
      let approverFailed = 0;

      if (approverQueueError) {
        console.error(
          "Unable to claim approver notification emails:",
          approverQueueError.message,
        );
      } else {
        for (const item of (approverQueue ?? []) as ApproverQueueItem[]) {
          const result = await processApproverQueueItem(item);
          if (result) {
            approverSent++;
          } else {
            approverFailed++;
          }
        }
      }
      // ---------------------------------------------------------
      // STATION OWNER EMAIL NOTIFICATIONS
      // ---------------------------------------------------------

      const { data: stationQueue, error: stationQueueError } = await db.rpc(
        "claim_fuel_request_station_emails",
        {
          p_batch_size: 10,
        },
      );

      let stationSent = 0;
      let stationFailed = 0;

      if (stationQueueError) {
        console.error(
          "Unable to claim station-owner email queue:",
          stationQueueError.message,
        );
      } else {
        for (const item of (stationQueue ?? []) as StationQueueItem[]) {
          const sent = await processStationQueueItem(item);

          if (sent) {
            stationSent++;
          } else {
            stationFailed++;
          }
        }
      }

      return Response.json({
        success: !omcQueueError && !approverQueueError && !stationQueueError,
        customer: {
          processed: sent + failed,
          sent,
          failed,
        },
        omc: {
          processed: omcSent + omcFailed,
          sent: omcSent,
          failed: omcFailed,
          queue_error: omcQueueError?.message ?? null,
        },

        approver: {
          processed: approverSent + approverFailed,
          sent: approverSent,
          failed: approverFailed,
          queue_error: approverQueueError?.message ?? null,
        },
        station: {
          processed: stationSent + stationFailed,
          sent: stationSent,
          failed: stationFailed,
          queue_error: stationQueueError?.message ?? null,
        },
      });
    },
  ),
};
