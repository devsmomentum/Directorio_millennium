-- =====================================================================
-- Flash Coupon: tabla de leads + RPC atómico para reclamar.
-- Lo invoca la Edge Function `claim-flash-coupon` (Supabase SMTP).
-- =====================================================================

-- 1. Tabla de leads capturados al reclamar un cupón flash.
CREATE TABLE IF NOT EXISTS public.coupon_leads (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id    uuid NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
  first_name   text NOT NULL,
  last_name    text NOT NULL,
  id_document  text NOT NULL,
  email        text NOT NULL,
  -- Trazabilidad del envío del correo (lo actualiza la Edge Function).
  email_sent_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT coupon_leads_email_format CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

-- Búsquedas típicas: leads de un cupón / lookup por correo.
CREATE INDEX IF NOT EXISTS coupon_leads_coupon_id_idx ON public.coupon_leads (coupon_id);
CREATE INDEX IF NOT EXISTS coupon_leads_email_idx     ON public.coupon_leads (lower(email));

-- Evita que un mismo correo reclame el mismo cupón dos veces.
CREATE UNIQUE INDEX IF NOT EXISTS coupon_leads_unique_per_coupon
  ON public.coupon_leads (coupon_id, lower(email));

-- 2. RLS: bloqueamos acceso directo. Sólo se entra vía RPC SECURITY DEFINER.
ALTER TABLE public.coupon_leads ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- RPC: reclama un cupón flash de forma atómica.
--   - Decrementa amount_available bajo lock de fila (UPDATE).
--   - Valida is_popup_active y end_date.
--   - Inserta el lead.
--   - Devuelve los datos que la Edge Function necesita para el correo.
-- Códigos de error (SQLSTATE P0001):
--   COUPON_UNAVAILABLE  -> agotado / inactivo / vencido / no existe
--   LEAD_DUPLICATE      -> mismo correo ya reclamó este cupón
-- =====================================================================
CREATE OR REPLACE FUNCTION public.claim_flash_coupon(
  p_coupon_id   uuid,
  p_first_name  text,
  p_last_name   text,
  p_id_document text,
  p_email       text
)
RETURNS TABLE (
  lead_id           uuid,
  coupon_code       text,
  coupon_title      text,
  coupon_image_url  text,
  coupon_price_usd  numeric,
  end_date          timestamptz,
  remaining         integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_remaining integer;
  v_code      text;
  v_title     text;
  v_image     text;
  v_price     numeric;
  v_end_date  timestamptz;
  v_lead_id   uuid;
BEGIN
  -- Decremento atómico + extracción de datos del cupón.
  UPDATE public.coupons
     SET amount_available = amount_available - 1
   WHERE id = p_coupon_id
     AND is_popup_active = true
     AND amount_available > 0
     AND (end_date IS NULL OR end_date > now())
   RETURNING amount_available, code, title, image_url, price_usd, end_date
        INTO v_remaining, v_code, v_title, v_image, v_price, v_end_date;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COUPON_UNAVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  -- Inserción del lead. Si el unique index dispara, devolvemos un error claro.
  BEGIN
    INSERT INTO public.coupon_leads (
      coupon_id, first_name, last_name, id_document, email
    )
    VALUES (
      p_coupon_id, p_first_name, p_last_name, p_id_document, p_email
    )
    RETURNING id INTO v_lead_id;
  EXCEPTION WHEN unique_violation THEN
    -- Si el lead ya existía, devolvemos el cupón decrementado al stock
    -- para no penalizar al usuario por un reintento.
    UPDATE public.coupons
       SET amount_available = amount_available + 1
     WHERE id = p_coupon_id;
    RAISE EXCEPTION 'LEAD_DUPLICATE' USING ERRCODE = 'P0001';
  END;

  RETURN QUERY
  SELECT v_lead_id, v_code, v_title, v_image, v_price, v_end_date, v_remaining;
END;
$$;

-- 3. Permisos: la Edge Function se autentica como `anon` o `authenticated`
-- según cómo invoques; abrimos ambos. Como es SECURITY DEFINER, el RPC
-- corre con los privilegios del owner y respeta su lógica.
REVOKE ALL ON FUNCTION public.claim_flash_coupon(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_flash_coupon(uuid, text, text, text, text)
  TO anon, authenticated, service_role;
