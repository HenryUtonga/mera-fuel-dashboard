type StationEmailDetails = {
  requestNumber: string;
  applicantName: string;
  stationName: string;
  omc: string;
  product: string;
  allocatedLitres: number;
  expiresAt: string;
  confirmUrl: string;
  notFueledUrl: string;
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

export function stationOwnerEmail(details: StationEmailDetails) {
  const reference = escapeHtml(details.requestNumber);
  const applicant = escapeHtml(details.applicantName);
  const station = escapeHtml(details.stationName);
  const omc = escapeHtml(details.omc);
  const product = escapeHtml(details.product);
  const litres = escapeHtml(details.allocatedLitres);
  const expiry = escapeHtml(details.expiresAt);

  const confirmUrl = escapeHtml(details.confirmUrl);
  const notFueledUrl = escapeHtml(details.notFueledUrl);

  return {
    subject: `MERA Fuel Authorization - ${details.requestNumber}`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#222;">
        <h2 style="color:#123b69;">MERA Fuel Authorization</h2>

        <p>A customer has been authorized to obtain fuel
        from your filling station.</p>

        <table style="border-collapse:collapse;width:100%;">
          <tr>
            <td style="padding:8px;border-bottom:1px solid #ddd;"><b>Reference</b></td>
            <td style="padding:8px;border-bottom:1px solid #ddd;">${reference}</td>
          </tr>
          <tr>
            <td style="padding:8px;border-bottom:1px solid #ddd;"><b>Customer</b></td>
            <td style="padding:8px;border-bottom:1px solid #ddd;">${applicant}</td>
          </tr>
          <tr>
            <td style="padding:8px;border-bottom:1px solid #ddd;"><b>Station</b></td>
            <td style="padding:8px;border-bottom:1px solid #ddd;">${station}</td>
          </tr>
          <tr>
            <td style="padding:8px;border-bottom:1px solid #ddd;"><b>OMC</b></td>
            <td style="padding:8px;border-bottom:1px solid #ddd;">${omc}</td>
          </tr>
          <tr>
            <td style="padding:8px;border-bottom:1px solid #ddd;"><b>Product</b></td>
            <td style="padding:8px;border-bottom:1px solid #ddd;">${product}</td>
          </tr>
          <tr>
            <td style="padding:8px;border-bottom:1px solid #ddd;"><b>Authorized Quantity</b></td>
            <td style="padding:8px;border-bottom:1px solid #ddd;">${litres} litres</td>
          </tr>
        </table>

        <p>Please report the fueling outcome using one of the options below.</p>

        <div style="margin:28px 0;">
          <a href="${confirmUrl}"
             style="background:#167347;color:white;padding:13px 20px;
                    text-decoration:none;border-radius:5px;
                    display:inline-block;margin:5px;">
            Confirm Fueling
          </a>

          <a href="${notFueledUrl}"
             style="background:#a83232;color:white;padding:13px 20px;
                    text-decoration:none;border-radius:5px;
                    display:inline-block;margin:5px;">
            Not Fueled
          </a>
        </div>

        <p><b>Confirm Fueling:</b> Enter the actual litres dispensed.</p>
        <p><b>Not Fueled:</b> Report that the customer did not receive fuel.
        MERA will review the allocation and decide whether to reallocate it.</p>

        <p style="font-size:13px;color:#666;">
          These links expire on ${expiry}.
          Clicking a button opens a confirmation form.
          No fueling outcome is recorded until you submit the form.
        </p>

        <p style="font-size:13px;color:#666;">
          This is an automated notification from the
          Malawi Energy Regulatory Authority (MERA).
          Please do not reply.
        </p>
      </div>
    `,
  };
}