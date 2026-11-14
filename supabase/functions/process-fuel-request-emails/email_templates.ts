
export type FuelRequest = {
  request_number: string;
  applicant_name: string;
  company_name: string | null;
  review_notes: string | null;
};

export type FuelAllocation = {
  product: string;
  station_name: string;
  omc: string | null;
  litres: number;
};

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (char) => {
    const replacements: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    };
    return replacements[char];
  });
}

function layout(title: string, content: string): string {
  return `
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
  </head>
  <body style="font-family:Arial,sans-serif;color:#243247;
               background:#f5f7fa;padding:24px;">
    <div style="max-width:650px;margin:auto;background:white;
                padding:28px;border-radius:8px;">
      <h2 style="color:#164b78;">MERA Fuel Control</h2>
      <h3>${escapeHtml(title)}</h3>
      ${content}
      <hr style="border:0;border-top:1px solid #ddd;margin-top:28px;">
      <p style="font-size:12px;color:#666;">
        Malawi Energy Regulatory Authority (MERA)<br>
        This is an automated notification concerning your fuel request.
      </p>
    </div>
  </body>
  </html>`;
}

export function approvalEmail(
  request: FuelRequest,
  allocations: FuelAllocation[],
): { subject: string; html: string } {
  const rows = allocations.map((allocation) => `
    <tr>
      <td>${escapeHtml(allocation.product)}</td>
      <td>${escapeHtml(allocation.station_name)}</td>
      <td>${escapeHtml(allocation.omc || "N/A")}</td>
      <td style="text-align:right;">
        ${escapeHtml(allocation.litres.toLocaleString("en-US", {
          maximumFractionDigits: 2,
        }))} L
      </td>
    </tr>
  `).join("");

  const html = layout("Fuel Request Approved", `
    <p>Dear ${escapeHtml(request.applicant_name)},</p>
    <p>Your fuel request
       <strong>${escapeHtml(request.request_number)}</strong>
       has been approved.</p>

    <p>The following fuel quantities have been allocated:</p>

    <table border="1" cellpadding="9" cellspacing="0"
           style="border-collapse:collapse;width:100%;">
      <thead>
        <tr style="background:#eef3f8;">
          <th>Product</th>
          <th>Filling Station</th>
          <th>OMC</th>
          <th>Allocated Litres</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>

    <p>Please present your approved request reference
       when visiting the allocated filling station.</p>
  `);

  return {
    subject: `MERA Fuel Request Approved - ${request.request_number}`,
    html,
  };
}

export function rejectionEmail(
  request: FuelRequest,
): { subject: string; html: string } {
  const html = layout("Fuel Request Rejected", `
    <p>Dear ${escapeHtml(request.applicant_name)},</p>

    <p>Your fuel request
       <strong>${escapeHtml(request.request_number)}</strong>
       has not been approved.</p>

    <p><strong>Reason:</strong><br>
       ${escapeHtml(request.review_notes || "Not specified")}</p>

    <p>For further clarification, please contact MERA.</p>
  `);

  return {
    subject: `MERA Fuel Request Rejected - ${request.request_number}`,
    html,
  };
}


export function omcApprovalEmail(
  request: FuelRequest,
  omcName: string,
  allocations: FuelAllocation[],
): { subject: string; html: string } {
  const rows = allocations.map((allocation) => `
    <tr>
      <td>${escapeHtml(allocation.product)}</td>
      <td>${escapeHtml(allocation.station_name)}</td>
      <td style="text-align:right;">
        ${escapeHtml(allocation.litres.toLocaleString("en-US", {
          maximumFractionDigits: 2,
        }))} L
      </td>
    </tr>
  `).join("");

  const html = layout("Approved Fuel Allocation Notification", `
    <p>Dear ${escapeHtml(omcName)} Team,</p>

    <p>The Malawi Energy Regulatory Authority (MERA)
       wishes to inform you that a fuel request has been
       approved for collection at your filling station(s).</p>

    <p><strong>Request Reference:</strong>
       ${escapeHtml(request.request_number)}</p>

    <p><strong>Customer:</strong>
       ${escapeHtml(request.applicant_name)}</p>

    ${request.company_name
      ? `<p><strong>Company:</strong>
           ${escapeHtml(request.company_name)}</p>`
      : ""}

    <p><strong>Approved Fuel Allocations:</strong></p>

    <table border="1" cellpadding="9" cellspacing="0"
           style="border-collapse:collapse;width:100%;">
      <thead>
        <tr style="background:#eef3f8;">
          <th>Product</th>
          <th>Filling Station</th>
          <th>Allocated Litres</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>

    <p>Kindly facilitate the approved fuel collection
       upon presentation and verification of the
       MERA fuel request reference.</p>

    <p>This notification applies only to the
       allocations listed above.</p>
  `);

  return {
    subject:
      `MERA Approved Fuel Allocation - ${request.request_number}`,
    html,
  };
}