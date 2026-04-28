// Edge Function: send-emergency-whatsapp
// ---------------------------------------------------------------------------
// Envía un mensaje de alerta de emergencia al grupo de WhatsApp configurado
// usando la API de iasuperapi.com.
//
// Variables de entorno requeridas (configurar con `supabase secrets set`):
//   SUPERAPI_TOKEN       Bearer token generado desde iasuperapi.com
//   WHATSAPP_GROUP_ID    chatId del grupo (ej: "120363xxxxxxxx@g.us")
//
// Variables opcionales:
//   SUPERAPI_PLATFORM    Plataforma (default: "wws")
//   SUPERAPI_CLIENT      Cliente en SuperAPI (si la cuenta tiene varias instancias)
//
// Las claves SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las inyecta Supabase
// automáticamente en runtime.
// ---------------------------------------------------------------------------

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

interface EmergencyRequest {
  kiosk_id?: string;
}

interface KioskRow {
  id: string;
  name: string;
  floor_level: string | null;
  location_name: string | null;
  location: string | null;
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

function buildMessage(kiosk: KioskRow, timestamp: string): string {
  const lines = [
    "🚨 *ALERTA DE EMERGENCIA* 🚨",
    "",
    `📍 *Kiosco:* ${kiosk.name}`,
  ];

  if (kiosk.floor_level) {
    lines.push(`🏢 *Piso:* ${kiosk.floor_level}`);
  }

  const loc = kiosk.location_name ?? kiosk.location;
  if (loc) {
    lines.push(`📌 *Ubicación:* ${loc}`);
  }

  lines.push(`🕐 *Hora:* ${timestamp}`);
  lines.push("");
  lines.push("⚠️ Se ha activado el protocolo de seguridad. Personal de seguridad debe acudir de inmediato.");

  return lines.join("\n");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  let payload: EmergencyRequest;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const kioskId = payload.kiosk_id?.trim() ?? "";
  if (!kioskId) {
    return jsonResponse(400, { error: "missing_kiosk_id" });
  }

  const superapiToken = Deno.env.get("SUPERAPI_TOKEN");
  const groupId = Deno.env.get("WHATSAPP_GROUP_ID");

  if (!superapiToken || !groupId) {
    console.error("[send-emergency-whatsapp] Env vars SUPERAPI_TOKEN or WHATSAPP_GROUP_ID missing");
    return jsonResponse(500, { error: "whatsapp_misconfigured" });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data, error: dbError } = await supabase
    .from("kiosks")
    .select("id, name, floor_level, location_name, location")
    .eq("id", kioskId)
    .single();

  if (dbError || !data) {
    console.error("[send-emergency-whatsapp] Kiosk not found:", dbError);
    return jsonResponse(404, { error: "kiosk_not_found" });
  }

  const kiosk = data as KioskRow;

  const now = new Date().toLocaleString("es-VE", {
    timeZone: "America/Caracas",
    dateStyle: "short",
    timeStyle: "medium",
  });

  const message = buildMessage(kiosk, now);

  const body: Record<string, unknown> = {
    chatId: groupId,
    message,
  };

  const platform = Deno.env.get("SUPERAPI_PLATFORM");
  const client = Deno.env.get("SUPERAPI_CLIENT");
  if (platform) body.platform = platform;
  if (client) body.client = client;

  let apiResponse: Response;
  try {
    apiResponse = await fetch("https://v4.iasuperapi.com/api/v1/send-message", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${superapiToken}`,
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.error("[send-emergency-whatsapp] Network error calling SuperAPI:", e);
    return jsonResponse(502, { error: "superapi_unreachable" });
  }

  const apiBody = await apiResponse.json().catch(() => ({}));

  if (!apiResponse.ok || apiBody.error) {
    console.error("[send-emergency-whatsapp] SuperAPI error:", apiResponse.status, apiBody);
    return jsonResponse(502, { error: "superapi_send_failed", detail: apiBody });
  }

  return jsonResponse(200, { ok: true, kiosk_id: kioskId });
});
