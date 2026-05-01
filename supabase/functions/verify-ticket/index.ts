import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  let barcode = ""
  try {
    const payload = await req.json()
    barcode = (payload?.barcode ?? "").toString().trim()
  } catch (_) {
    barcode = ""
  }

  if (!barcode) {
    const url = new URL(req.url)
    barcode = url.searchParams.get("barcode")?.trim() ?? ""
  }

  if (!barcode) {
    return new Response(
      JSON.stringify({ error: "barcode is required" }),
      { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } },
    )
  }

  const username = Deno.env.get("ESTA7_USERNAME")
  const password = Deno.env.get("ESTA7_PASSWORD")
  if (!username || !password) {
    return new Response(
      JSON.stringify({ error: "missing ESTA7 credentials" }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } },
    )
  }

  const auth = btoa(`${username}:${password}`)

  try {
    const response = await fetch(`https://esta7.com/ticket/verify/${barcode}`, {
      method: "GET",
      headers: {
        "Authorization": `Basic ${auth}`,
        "Content-Type": "application/json",
      },
    })

    const text = await response.text()
    console.log(`[verify-ticket] Response from esta7 (barcode: ${barcode}): status=${response.status} body=${text}`)

    let data
    try {
      data = JSON.parse(text)
    } catch (_) {
      data = { raw: text }
    }

    // El sistema retorna status: "valid" o "invalid".
    return new Response(JSON.stringify(data), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
      status: response.status,
    })
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } },
    )
  }
})