-- =====================================================================
-- Cupones: la regla "es flash" pasa de la bandera `is_popup_active` al
-- valor `plan_type = 'PUBLI_PROMO'`. Además, `end_date` deja de ser
-- opcional: TODO cupón debe declarar fecha límite.
--
-- Cambios:
--   1. Amplía el CHECK de `plan_type` con 'PUBLI_PROMO'.
--   2. Backfill de `plan_type` <- 'PUBLI_PROMO' para los pop-up actuales
--      y de `end_date` para cualquier fila sin vencimiento.
--   3. `end_date` pasa a NOT NULL.
--   4. Drop de la columna `is_popup_active` (ya no se consulta).
--   5. Reescribe los RPC `claim_flash_coupon` y `claim_catalog_coupon`
--      para usar la nueva regla.
-- =====================================================================

-- 1. Ampliar el dominio de plan_type para aceptar 'PUBLI_PROMO'.
ALTER TABLE public.coupons
  DROP CONSTRAINT IF EXISTS coupons_plan_type_check;

ALTER TABLE public.coupons
  ADD CONSTRAINT coupons_plan_type_check
  CHECK (plan_type = ANY (ARRAY[
    'DIAMANTE'::text,
    'ORO'::text,
    'IA_PERFORMANCE'::text,
    'BONO_PREMIADO'::text,
    'PUBLI_PROMO'::text
  ]));

-- 2. Backfill: cualquier cupón que hoy era flash queda como PUBLI_PROMO,
--    y los que no tienen end_date reciben +30 días para no romper el
--    NOT NULL del paso 3 (decisión conservadora; ajustar a mano si hace falta).
UPDATE public.coupons
   SET plan_type = 'PUBLI_PROMO'
 WHERE is_popup_active = TRUE
   AND plan_type <> 'PUBLI_PROMO';

UPDATE public.coupons
   SET end_date = COALESCE(start_date, now()) + interval '30 days'
 WHERE end_date IS NULL;

-- 3. end_date obligatorio para todos los cupones.
ALTER TABLE public.coupons
  ALTER COLUMN end_date SET NOT NULL;

-- 4. Eliminamos la columna is_popup_active: la regla vive ahora en plan_type.
ALTER TABLE public.coupons
  DROP COLUMN IF EXISTS is_popup_active;

-- 5. RPC del flash: ahora exige plan_type = 'PUBLI_PROMO' (antes is_popup_active).
--    end_date ya no admite NULL, así que la guarda se simplifica a `end_date > now()`.
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
  UPDATE public.coupons
     SET amount_available = amount_available - 1
   WHERE id = p_coupon_id
     AND plan_type = 'PUBLI_PROMO'
     AND amount_available > 0
     AND end_date > now()
   RETURNING amount_available, code, title, image_url, price_usd, end_date
        INTO v_remaining, v_code, v_title, v_image, v_price, v_end_date;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COUPON_UNAVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    INSERT INTO public.coupon_leads (
      coupon_id, first_name, last_name, id_document, email
    )
    VALUES (
      p_coupon_id, p_first_name, p_last_name, p_id_document, p_email
    )
    RETURNING id INTO v_lead_id;
  EXCEPTION WHEN unique_violation THEN
    UPDATE public.coupons
       SET amount_available = amount_available + 1
     WHERE id = p_coupon_id;
    RAISE EXCEPTION 'LEAD_DUPLICATE' USING ERRCODE = 'P0001';
  END;

  RETURN QUERY
  SELECT v_lead_id, v_code, v_title, v_image, v_price, v_end_date, v_remaining;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_flash_coupon(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_flash_coupon(uuid, text, text, text, text)
  TO anon, authenticated, service_role;

-- 6. RPC del catálogo: end_date ya es NOT NULL, así que retiramos la
--    tolerancia a NULL. La regla "todos los cupones vigentes" se mantiene.
CREATE OR REPLACE FUNCTION public.claim_catalog_coupon(
  p_coupon_id uuid,
  p_email     text
)
RETURNS TABLE (
  lead_id          uuid,
  coupon_code      text,
  coupon_title     text,
  coupon_image_url text,
  end_date         timestamptz,
  remaining        integer
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
  v_end_date  timestamptz;
  v_lead_id   uuid;
BEGIN
  UPDATE public.coupons
     SET amount_available = amount_available - 1
   WHERE id = p_coupon_id
     AND amount_available > 0
     AND end_date > now()
   RETURNING amount_available, code, title, image_url, end_date
        INTO v_remaining, v_code, v_title, v_image, v_end_date;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COUPON_UNAVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    INSERT INTO public.coupon_leads (coupon_id, email)
    VALUES (p_coupon_id, p_email)
    RETURNING id INTO v_lead_id;
  EXCEPTION WHEN unique_violation THEN
    UPDATE public.coupons
       SET amount_available = amount_available + 1
     WHERE id = p_coupon_id;
    RAISE EXCEPTION 'LEAD_DUPLICATE' USING ERRCODE = 'P0001';
  END;

  RETURN QUERY
  SELECT v_lead_id, v_code, v_title, v_image, v_end_date, v_remaining;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_catalog_coupon(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_catalog_coupon(uuid, text)
  TO anon, authenticated, service_role;
