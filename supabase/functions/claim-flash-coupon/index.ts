// Edge Function: claim-flash-coupon
// ---------------------------------------------------------------------------
// Reclama un cupón flash de forma atómica (vía RPC) y envía el correo SMTP
// con el código del cupón y la fecha de expiración.
//
// Variables de entorno requeridas (configurar con `supabase secrets set`):
//   SMTP_HOST       p.ej. smtp.resend.com / smtp.gmail.com / etc.
//   SMTP_PORT       587 (STARTTLS) | 465 (TLS)
//   SMTP_USERNAME
//   SMTP_PASSWORD
//   SMTP_FROM       "Milemium <no-reply@tudominio.com>"
//
// Las claves SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las inyecta Supabase
// automáticamente en runtime — no hay que setearlas como secrets.
// ---------------------------------------------------------------------------

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

interface ClaimRequest {
  coupon_id?: string;
  first_name?: string;
  last_name?: string;
  id_document?: string;
  email?: string;
}

interface ClaimRpcRow {
  lead_id: string;
  coupon_code: string | null;
  coupon_title: string;
  coupon_image_url: string | null;
  coupon_price_usd: number;
  end_date: string | null;
  remaining: number;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function buildEmail(input: {
  firstName: string;
  couponTitle: string;
  couponCode: string | null;
  endDate: string | null;
  remaining: number;
}): { subject: string; html: string; text: string } {
  const expiry = input.endDate
    ? new Date(input.endDate).toLocaleString("es-VE", {
        dateStyle: "full",
        timeStyle: "short",
      })
    : "tiempo limitado";

  const codeBlock = input.couponCode ?? "(sin código)";
  const safeName = escapeHtml(input.firstName);
  const safeTitle = escapeHtml(input.couponTitle);
  const safeCode = escapeHtml(codeBlock);

  const subject = `🎟️ Tu Flash Coupon: ${input.couponTitle}`;

  const html = `
    <div style="font-family:system-ui,-apple-system,Segoe UI,sans-serif;max-width:520px;margin:auto;padding:24px;background:#fff;color:#111">
      <h1 style="color:#e53935;margin:0 0 8px">¡Hola ${safeName}!</h1>
      <p style="font-size:16px;line-height:1.5">
        Tu cupón flash <strong>${safeTitle}</strong> ya está reservado a tu nombre.
      </p>
      <div style="margin:24px 0;padding:20px;border:2px dashed #e53935;border-radius:12px;text-align:center">
        <div style="font-size:12px;letter-spacing:2px;color:#666">CÓDIGO</div>
        <div style="font-size:28px;font-weight:900;letter-spacing:3px;color:#e53935;margin-top:8px">
          ${safeCode}
        </div>
      </div>
      <p style="font-size:14px;color:#444">
        ⏰ <strong>Vence:</strong> ${escapeHtml(expiry)}<br/>
        ⚠️ <strong>Solo quedan ${input.remaining} cupones disponibles.</strong> ¡No esperes a que se agoten!
      </p>
      <p style="font-size:12px;color:#888;margin-top:32px">
        Presenta este correo o el código en el establecimiento para canjear tu beneficio.
      </p>
    </div>
  `;

  const text = [
    `Hola ${input.firstName},`,
    ``,
    `Tu cupón flash "${input.couponTitle}" está reservado a tu nombre.`,
    ``,
    `Código: ${codeBlock}`,
    `Vence: ${expiry}`,
    `Solo quedan ${input.remaining} cupones disponibles.`,
    ``,
    `Presenta este correo o el código en el establecimiento para canjear.`,
  ].join("\n");

  return { subject, html, text };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  let payload: ClaimRequest;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const couponId = payload.coupon_id?.trim() ?? "";
  const firstName = payload.first_name?.trim() ?? "";
  const lastName = payload.last_name?.trim() ?? "";
  const idDocument = payload.id_document?.trim() ?? "";
  const email = payload.email?.trim().toLowerCase() ?? "";

  if (!couponId || !firstName || !lastName || !idDocument || !email) {
    return jsonResponse(400, { error: "missing_fields" });
  }
  if (!isValidEmail(email)) {
    return jsonResponse(400, { error: "invalid_email" });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // 1) RPC atómico: decrementa stock, inserta lead, devuelve datos del cupón.
  const { data, error } = await supabase.rpc("claim_flash_coupon", {
    p_coupon_id: couponId,
    p_first_name: firstName,
    p_last_name: lastName,
    p_id_document: idDocument,
    p_email: email,
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("COUPON_UNAVAILABLE")) {
      return jsonResponse(409, { error: "coupon_unavailable" });
    }
    if (msg.includes("LEAD_DUPLICATE")) {
      return jsonResponse(409, { error: "lead_duplicate" });
    }
    console.error("[claim-flash-coupon] RPC error:", error);
    return jsonResponse(500, { error: "rpc_failed" });
  }

  // El RPC devuelve TABLE => array de filas. Tomamos la primera.
  const row: ClaimRpcRow | undefined = Array.isArray(data) ? data[0] : data;
  if (!row) {
    console.error("[claim-flash-coupon] RPC returned empty result");
    return jsonResponse(500, { error: "rpc_empty" });
  }

  // 2) Envío SMTP. Si falla, NO revertimos el cupón: el lead ya quedó
  //    registrado y el negocio puede reenviar el correo manualmente.
  const { subject, html, text } = buildEmail({
    firstName,
    couponTitle: row.coupon_title,
    couponCode: row.coupon_code,
    endDate: row.end_date,
    remaining: row.remaining,
  });

  const smtpHost = Deno.env.get("SMTP_HOST");
  const smtpPort = Number(Deno.env.get("SMTP_PORT") ?? "587");
  const smtpUser = Deno.env.get("SMTP_USERNAME");
  const smtpPass = Deno.env.get("SMTP_PASSWORD");
  const smtpFrom = Deno.env.get("SMTP_FROM");

  if (!smtpHost || !smtpUser || !smtpPass || !smtpFrom) {
    console.error("[claim-flash-coupon] SMTP env vars missing");
    return jsonResponse(500, {
      error: "smtp_misconfigured",
      lead_id: row.lead_id,
    });
  }

  const client = new SMTPClient({
    connection: {
      hostname: smtpHost,
      port: smtpPort,
      // 465 = TLS implícito; 587 = STARTTLS.
      tls: smtpPort === 465,
      auth: { username: smtpUser, password: smtpPass },
    },
  });

  try {
    await client.send({
      from: smtpFrom,
      to: email,
      subject,
      content: text,
      html,
    });
    await client.close();
  } catch (e) {
    console.error("[claim-flash-coupon] SMTP send error:", e);
    try { await client.close(); } catch { /* ignore */ }
    return jsonResponse(502, {
      error: "smtp_send_failed",
      lead_id: row.lead_id,
    });
  }

  // 3) Marca el lead como notificado (best-effort).
  const { error: updateError } = await supabase
    .from("coupon_leads")
    .update({ email_sent_at: new Date().toISOString() })
    .eq("id", row.lead_id);
  if (updateError) {
    console.warn(
      "[claim-flash-coupon] no se pudo marcar email_sent_at:",
      updateError,
    );
  }

  return jsonResponse(200, {
    ok: true,
    lead_id: row.lead_id,
    remaining: row.remaining,
  });
});
