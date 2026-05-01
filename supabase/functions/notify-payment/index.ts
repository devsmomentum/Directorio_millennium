import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { barcode, paymentOrder } = await req.json()
  
  const username = Deno.env.get('ESTA7_USERNAME')
  const password = Deno.env.get('ESTA7_PASSWORD')
  const auth = btoa(`${username}:${password}`)

  // Payload opcional para auditoría interna del mall [cite: 65, 76]
  const payload = {
    transactionId: paymentOrder.id, // ID de tu pasarela
    name: "Pago App Centro Comercial"
  }

  try {
    const response = await fetch(`https://esta7.com/ticket/notify/${barcode}`, {
      method: 'GET', // El documento especifica GET incluso para notificar [cite: 58]
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json'
      }
      // Si el servidor acepta el body en GET, se incluye; si no, el barcode es suficiente.
    })

    const data = await response.json()
    
    // Si es válido, retorna un "code" para la factura (opcional) [cite: 97, 98]
    return new Response(JSON.stringify(data), { 
      headers: { "Content-Type": "application/json" } 
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})