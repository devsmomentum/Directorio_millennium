import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-source',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
    // Manejar OPTIONS para CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    // 1. Validar que sea una solicitud POST
    if (req.method !== 'POST') {
        return new Response(JSON.stringify({ error: 'Method Not Allowed' }), {
            status: 405,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }

    // 2. Validar el header de autenticidad (x-webhook-source)
    const webhookSource = req.headers.get('x-webhook-source')
    if (webhookSource !== 'pagoapago-payment-processor') {
        return new Response(JSON.stringify({ error: 'Unauthorized' }), {
            status: 401,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }

    try {
        // 3. Parsear el JSON del body
        const payload = await req.json()
        const { event, data } = payload

        console.log(`[webhook-PAP] Evento recibido: ${event}, order_id: ${data?.order_id}`)

        if (!event || !data || !data.order_id) {
            return new Response(JSON.stringify({ error: 'Bad Request: Missing required fields' }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        // Configurar el cliente de Supabase
        // Utilizamos el SERVICE_ROLE_KEY para ignorar las políticas RLS,
        // ya que este es un proceso backend autorizado.
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // 4. Extraer datos y preparar la lógica de procesamiento
        let statusUpdate = ''
        let updatePayload: Record<string, any> = {}

        // Evaluar el tipo de evento
        switch (event) {
            case 'payment.paid':
            case 'payment.completed':
                statusUpdate = 'completed'
                updatePayload = {
                    status: statusUpdate,
                    transaction_id: data.transaction_id,
                    reference: data.reference,
                    paid_at: data.paid_at,
                    updated_at: new Date().toISOString(),
                }
                break

            case 'payment.failed':
            case 'payment.error':
                statusUpdate = 'failed'
                updatePayload = {
                    status: statusUpdate,
                    updated_at: new Date().toISOString(),
                }
                break

            case 'payment.cancelled':
                statusUpdate = 'cancelled'
                updatePayload = {
                    status: statusUpdate,
                    updated_at: new Date().toISOString(),
                }
                break

            case 'payment.expired':
                statusUpdate = 'cancelled'
                updatePayload = {
                    status: statusUpdate,
                    updated_at: new Date().toISOString(),
                }
                break

            default:
                console.warn(`[webhook-PAP] Evento no manejado o desconocido: ${event}`)
                // Retornamos 200 OK para eventos ignorados para que no se reintenten innecesariamente
                return new Response(JSON.stringify({ message: "Evento ignorado" }), {
                    status: 200,
                    headers: { ...corsHeaders, "Content-Type": "application/json" },
                })
        }

        // 5. Actualizar el estado de la orden en pap_payment_orders
        const { error: orderError } = await supabase
            .from('pap_payment_orders')
            .update(updatePayload)
            .eq('order_id', data.order_id)

        if (orderError) {
            console.error('[webhook-PAP] Error actualizando pap_payment_orders:', orderError)
            throw new Error(orderError.message)
        }

        console.log(`[webhook-PAP] pap_payment_orders actualizada: order_id=${data.order_id} status=${statusUpdate}`)

        // 6. Si es pago exitoso → actualizar parking_tickets + notificar a Esta7
        if (statusUpdate === 'completed') {
            // Obtener el barcode asociado a la orden
            const { data: orderData, error: fetchError } = await supabase
                .from('pap_payment_orders')
                .select('barcode')
                .eq('order_id', data.order_id)
                .single()

            if (fetchError || !orderData?.barcode) {
                console.error(`[webhook-PAP] No se encontró barcode para order_id=${data.order_id}:`, fetchError)
            } else {
                const barcode = orderData.barcode
                console.log(`[webhook-PAP] Barcode encontrado: ${barcode}. Actualizando parking_tickets...`)

                // 6a. Marcar el ticket como pagado en la BD
                const { error: ticketError } = await supabase
                    .from('parking_tickets')
                    .update({ status: 'paid' })
                    .eq('barcode', barcode)

                if (ticketError) {
                    console.error(`[webhook-PAP] Error actualizando parking_tickets:`, ticketError)
                } else {
                    console.log(`[webhook-PAP] parking_tickets actualizado a 'paid' para barcode=${barcode}`)
                }

                // 6b. Notificar a Esta7 para abrir la barrera de salida
                try {
                    const esta7Username = Deno.env.get('ESTA7_USERNAME')
                    const esta7Password = Deno.env.get('ESTA7_PASSWORD')

                    if (esta7Username && esta7Password) {
                        const auth = btoa(`${esta7Username}:${esta7Password}`)

                        const notifyRes = await fetch(
                            `https://esta7.com/ticket/notify/${barcode}`,
                            {
                                method: 'GET',
                                headers: {
                                    'Authorization': `Basic ${auth}`,
                                    'Content-Type': 'application/json',
                                },
                            }
                        )

                        const notifyText = await notifyRes.text()
                        console.log(`[webhook-PAP] Esta7 notify response (barcode=${barcode}): status=${notifyRes.status} body=${notifyText}`)

                        // Guardar exit_code si Esta7 lo devuelve
                        try {
                            const notifyData = JSON.parse(notifyText)
                            if (notifyData?.code) {
                                await supabase
                                    .from('parking_tickets')
                                    .update({ exit_code: notifyData.code })
                                    .eq('barcode', barcode)
                                console.log(`[webhook-PAP] exit_code guardado: ${notifyData.code}`)
                            }
                        } catch (_) {
                            // Respuesta no JSON de Esta7, ignorar
                        }
                    } else {
                        console.warn('[webhook-PAP] Credenciales de Esta7 no configuradas. Notify omitido.')
                    }
                } catch (notifyErr) {
                    // No lanzamos error — el pago ya se procesó exitosamente.
                    // La notificación a Esta7 puede reintentarse manualmente si falla.
                    console.error('[webhook-PAP] Error notificando a Esta7:', notifyErr)
                }
            }
        }

        // 7. Responder HTTP 200 OK
        return new Response(JSON.stringify({ received: true, status: statusUpdate }), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        })

    } catch (error) {
        console.error('[webhook-PAP] Error interno procesando el webhook:', error)
        return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }
})