import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { barcode } = await req.json()
  
  const username = Deno.env.get('ESTA7_USERNAME')
  const password = Deno.env.get('ESTA7_PASSWORD')
  const auth = btoa(`${username}:${password}`)

  try {
    const response = await fetch(`https://esta7.com/ticket/verify/${barcode}`, {
      method: 'GET',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json'
      }
    })

    const data = await response.json()
    
    // El sistema retorna status: "valid" o "invalid" [cite: 85, 90]
    return new Response(JSON.stringify(data), { 
      headers: { "Content-Type": "application/json" },
      status: response.status 
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})