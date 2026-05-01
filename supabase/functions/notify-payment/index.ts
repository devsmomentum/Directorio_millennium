import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Manejar OPTIONS para CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // 1. Asegurar que la petición sea POST
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: "Method Not Allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }

  // 2. Parseo seguro del JSON
  let body;
  try {
    body = await req.json();
  } catch (error) {
    return new Response(JSON.stringify({ error: "Cuerpo de la petición inválido o vacío. Se esperaba un JSON válido." }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }

  const { barcode, paymentOrder } = body;

  const username = Deno.env.get('ESTA7_USERNAME')
  const password = Deno.env.get('ESTA7_PASSWORD')
  const auth = btoa(`${username}:${password}`)
  
  // Payload opcional para auditoría interna del mall
  const payload = {
    transactionId: paymentOrder?.id || "simulated_transaction", // ID de tu pasarela
    name: "Pago App Centro Comercial"
  }

  try {
    const response = await fetch(`https://esta7.com/ticket/notify/${barcode}`, {
      method: 'GET', // El documento especifica GET incluso para notificar
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json'
      }
    })

    const text = await response.text()
    console.log(`[notify-payment] Response from esta7 (barcode: ${barcode}): status=${response.status} body=${text}`)

    let data
    try {
      data = JSON.parse(text)
    } catch (_) {
      data = { raw: text }
    }

    // Si es válido, retorna un "code" para la factura (opcional)
    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  }
})