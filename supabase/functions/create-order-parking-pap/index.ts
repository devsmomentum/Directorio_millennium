import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  // Manejo de solicitudes CORS preflight (Opcional pero recomendado)
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    });
  }

  try {
    // 1. Extraer los datos enviados por el cliente
    const { amount, expires_at } = await req.json();

    // 2. Validar que ambos campos existan
    if (!amount || !expires_at) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          message: "Los campos 'amount' y 'expires_at' son obligatorios." 
        }),
        { 
          status: 400, 
          headers: { "Content-Type": "application/json" } 
        }
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
        expires_at: expires_at
      })
    });

    // 5. Capturar la respuesta de la pasarela
    const data = await apiResponse.json();

    // 6. Devolver la respuesta (que incluye payment_url y order_id) a tu cliente
    return new Response(
      JSON.stringify(data),
      { 
        status: apiResponse.status, 
        headers: { 
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*" 
        } 
      }
    );

  } catch (error) {
    // Manejo de errores internos
    return new Response(
      JSON.stringify({ 
        success: false, 
        message: "Error interno procesando el pago", 
        error: error.message 
      }),
      { 
        status: 500, 
        headers: { "Content-Type": "application/json" } 
      }
    );
  }
});