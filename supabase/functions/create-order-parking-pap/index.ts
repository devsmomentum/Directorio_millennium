import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Manejo de solicitudes CORS preflight (Opcional pero recomendado)
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  try {
    // 1. Extraer los datos enviados por el cliente
    const rawBody = await req.text();
    let payload: Record<string, unknown> = {};
    try {
      payload = rawBody ? JSON.parse(rawBody) : {};
    } catch (_) {
      payload = {};
    }

    console.log(
      "[create-order-parking-pap] bodyLength=",
      rawBody.length,
      "keys=",
      Object.keys(payload),
    );

    const amount = payload.amount;
    const barcode = payload.barcode;
    const payment_method = payload.payment_method;

    // 2. Validar que ambos campos existan
    if (amount === undefined || amount === null) {
      console.log(
        "[create-order-parking-pap] missing field amount",
        { amount },
      );
      return new Response(
        JSON.stringify({
          success: false,
          message: "El campo 'amount' es obligatorio.",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        },
      );
    }
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

    if (!barcode) {
      console.log("[create-order-parking-pap] missing barcode", { barcode });
      return new Response(
        JSON.stringify({
          success: false,
          message: "El campo 'barcode' es obligatorio.",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        },
      );
    }

    // 3. Obtener la API Key desde las variables de entorno del servidor
    const apiKey = Deno.env.get("PAGOAPAGO_API_KEY");
    
    if (!apiKey) {
        throw new Error("La clave API de PagoaPago no está configurada en el servidor.");
    }

    // 4. Realizar la petición a la pasarela Pago a Pago
    const pagoAPagoUrl = "https://mqlboutjgscjgogqbsjc.supabase.co/functions/v1/api_pay_orders";
    
    const apiResponse = await fetch(pagoAPagoUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "pago_pago_api": apiKey
      },
      body: JSON.stringify({
        amount: amount,
        expires_at: expiresAt,
      })
    });

    // 5. Capturar la respuesta de la pasarela
    const apiText = await apiResponse.text();
    let data: Record<string, unknown> = {};
    try {
      data = apiText ? JSON.parse(apiText) : {};
    } catch (_) {
      data = { raw: apiText };
    }

    console.log(
      `[create-order-parking-pap] gateway response status=${apiResponse.status} body=${apiText}`
    );

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Supabase service role no configurado.");
    }

    const gatewayData = (data as Record<string, unknown>)?.data ?? data;
    const orderId =
      (gatewayData as Record<string, unknown>)?.order_id ??
      (gatewayData as Record<string, unknown>)?.orderId ??
      (gatewayData as Record<string, unknown>)?.id ??
      "";
    const urlPayment =
      (gatewayData as Record<string, unknown>)?.url_payment ??
      (gatewayData as Record<string, unknown>)?.urlPayment ??
      (gatewayData as Record<string, unknown>)?.payment_url ??
      "";
    const status =
      (gatewayData as Record<string, unknown>)?.status ?? "pending";

    if (!orderId) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "La pasarela no devolvio order_id.",
          data,
        }),
        {
          status: 502,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        },
      );
    }

    const supabase = createClient(
      supabaseUrl,
      serviceRoleKey,
      { auth: { persistSession: false } },
    );

    const { error: ticketError } = await supabase
      .from("parking_tickets")
      .upsert({
        barcode: barcode,
        status: "pending",
      }, { onConflict: "barcode" });

    if (ticketError) {
      console.error(
        "[create-order-parking-pap] parking_tickets upsert error:",
        ticketError,
      );
      return new Response(
        JSON.stringify({
          success: false,
          message: "No se pudo preparar el ticket en Supabase.",
          error: ticketError.message,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        },
      );
    }

    const { error: insertError } = await supabase
      .from("pap_payment_orders")
      .upsert({
        order_id: orderId,
        barcode: barcode,
        amount: amount,
        url_payment: urlPayment,
        status: status,
        payment_method: payment_method ?? null,
      }, { onConflict: "order_id" });

    if (insertError) {
      console.error(
        "[create-order-parking-pap] insert error:",
        insertError,
      );
      return new Response(
        JSON.stringify({
          success: false,
          message: "No se pudo guardar la orden en Supabase.",
          error: insertError.message,
          data,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        },
      );
    }

    // 6. Devolver la respuesta (que incluye payment_url y order_id) a tu cliente
    return new Response(
      JSON.stringify({
        order_id: orderId,
        payment_url: urlPayment,
        status: status,
        raw: data,
      }),
      {
        status: apiResponse.status,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      },
    );

  } catch (error) {
    // Manejo de errores internos
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({
        success: false,
        message: "Error interno procesando el pago",
        error: message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      },
    );
  }
});