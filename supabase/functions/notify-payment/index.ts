import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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

  if (!barcode) {
    return new Response(JSON.stringify({ error: "El campo 'barcode' es obligatorio." }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }

  console.log(`[notify-payment] Procesando notificación para barcode=${barcode}`)

  // Configurar Supabase con service role para bypass RLS
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  let supabase: ReturnType<typeof createClient> | null = null
  if (supabaseUrl && serviceRoleKey) {
    supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    })
  } else {
    console.warn('[notify-payment] Supabase service role no configurado. No se actualizará la BD.')
  }

  // 3. Actualizar parking_tickets a 'paid' en la BD (idempotente)
  if (supabase) {
    const { error: ticketError } = await supabase
      .from('parking_tickets')
      .update({ status: 'paid' })
      .eq('barcode', barcode)

    if (ticketError) {
      console.error(`[notify-payment] Error actualizando parking_tickets:`, ticketError)
    } else {
      console.log(`[notify-payment] parking_tickets actualizado a 'paid' para barcode=${barcode}`)
    }

    // Actualizar la orden asociada si existe
    if (paymentOrder?.id) {
      const { error: orderError } = await supabase
        .from('pap_payment_orders')
        .update({ status: 'completed', updated_at: new Date().toISOString() })
        .eq('order_id', paymentOrder.id)

      if (orderError) {
        console.error(`[notify-payment] Error actualizando pap_payment_orders:`, orderError)
      }
    }
  }

  // 4. Notificar a Esta7 para abrir la barrera
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

    // Guardar exit_code si Esta7 lo devuelve
    if (supabase && data?.code) {
      await supabase
        .from('parking_tickets')
        .update({ exit_code: data.code })
        .eq('barcode', barcode)
      console.log(`[notify-payment] exit_code guardado: ${data.code}`)
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