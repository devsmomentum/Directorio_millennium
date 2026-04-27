// Edge Function: claim-catalog-coupon
// ---------------------------------------------------------------------------
// Reclama un cupón del catálogo (pestaña Cupones) de forma atómica vía RPC y
// envía el correo SMTP con el código de canjeo. A diferencia del flash, no
// hay pago ni captura de nombre/cédula: el catálogo es un canje gratuito y
// el único dato del usuario es el correo.
//
// Variables de entorno (configurar con `supabase secrets set`):
//   SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase en runtime.
// ---------------------------------------------------------------------------

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

interface ClaimRequest {
  coupon_id?: string;
  email?: string;
}

interface ClaimRpcRow {
  lead_id: string;
  coupon_code: string | null;
  coupon_title: string;
  coupon_image_url: string | null;
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
  const safeTitle = escapeHtml(input.couponTitle);
  const safeCode = escapeHtml(codeBlock);

  const subject = `🎟️ Tu cupón Milemium: ${input.couponTitle}`;

  const html = `
    <div style="font-family:system-ui,-apple-system,Segoe UI,sans-serif;max-width:520px;margin:auto;padding:24px;background:#fff;color:#111">
      <h1 style="color:#00838f;margin:0 0 8px">¡Tu cupón está listo!</h1>
      <p style="font-size:16px;line-height:1.5">
        Reclamaste <strong>${safeTitle}</strong>. Presenta este código en la
        tienda para canjearlo.
      </p>
      <div style="margin:24px 0;padding:20px;border:2px dashed #00838f;border-radius:12px;text-align:center">
        <div style="font-size:12px;letter-spacing:2px;color:#666">CÓDIGO DE CANJEO</div>
        <div style="font-size:28px;font-weight:900;letter-spacing:3px;color:#00838f;margin-top:8px">
          ${safeCode}
        </div>
      </div>
      <p style="font-size:14px;color:#444">
        ⏰ <strong>Vence:</strong> ${escapeHtml(expiry)}<br/>
        🎁 <strong>Cupones restantes:</strong> ${input.remaining}
      </p>
      <p style="font-size:12px;color:#888;margin-top:32px">
        Canje sin costo. Presenta este correo o el código en el establecimiento.
      </p>
    </div>
  `;

  const text = [
    `¡Tu cupón está listo!`,
    ``,
    `Reclamaste "${input.couponTitle}".`,
    ``,
    `Código de canjeo: ${codeBlock}`,
    `Vence: ${expiry}`,
    `Cupones restantes: ${input.remaining}`,
    ``,
    `Canje sin costo. Presenta este correo o el código en el establecimiento.`,
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
  const email = payload.email?.trim().toLowerCase() ?? "";

  if (!couponId || !email) {
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

  const { data, error } = await supabase.rpc("claim_catalog_coupon", {
    p_coupon_id: couponId,
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
    console.error("[claim-catalog-coupon] RPC error:", error);
    return jsonResponse(500, { error: "rpc_failed" });
  }

  const row: ClaimRpcRow | undefined = Array.isArray(data) ? data[0] : data;
  if (!row) {
    console.error("[claim-catalog-coupon] RPC returned empty result");
    return jsonResponse(500, { error: "rpc_empty" });
  }

  const { subject, html, text } = buildEmail({
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
    console.error("[claim-catalog-coupon] SMTP env vars missing");
    return jsonResponse(500, {
      error: "smtp_misconfigured",
      lead_id: row.lead_id,
    });
  }

  const client = new SMTPClient({
    connection: {
      hostname: smtpHost,
      port: smtpPort,
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
    console.error("[claim-catalog-coupon] SMTP send error:", e);
    try { await client.close(); } catch { /* ignore */ }
    return jsonResponse(502, {
      error: "smtp_send_failed",
      lead_id: row.lead_id,
    });
  }

  const { error: updateError } = await supabase
    .from("coupon_leads")
    .update({ email_sent_at: new Date().toISOString() })
    .eq("id", row.lead_id);
  if (updateError) {
    console.warn(
      "[claim-catalog-coupon] no se pudo marcar email_sent_at:",
      updateError,
    );
  }

  return jsonResponse(200, {
    ok: true,
    lead_id: row.lead_id,
    remaining: row.remaining,
  });
});
