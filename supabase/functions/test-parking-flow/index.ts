import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async () => {
  const testBarcode = "2388902010051619" // Código que siempre es válido [cite: 140]
  
  // 1. Simular Verificación
  const verifyRes = await fetch(`https://esta7.com/ticket/verify/${testBarcode}`, {
    headers: { 'Authorization': `Basic ${btoa("prueba:prueba")}` }
  })
  const verifyData = await verifyRes.json()

  // 2. Simular Notificación
  const notifyRes = await fetch(`https://esta7.com/ticket/notify/${testBarcode}`, {
    headers: { 'Authorization': `Basic ${btoa("prueba:prueba")}` }
  })
  const notifyData = await notifyRes.json()

  return new Response(JSON.stringify({
    description: "Resultados de la prueba de integración con Esta7",
    step1_verify: verifyData,
    step2_notify: notifyData
  }), { headers: { "Content-Type": "application/json" } })
})