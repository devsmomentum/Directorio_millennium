-- =====================================================================
-- Catálogo de Cupones: RPC atómico para RECLAMAR un cupón desde la
-- pestaña Cupones (CouponsScreen) y registrar el lead.
--
-- Los cupones del catálogo NO se pagan: se reclaman gratuitamente y el
-- usuario recibe el código de canjeo por correo. La RPC reemplaza al
-- antiguo flujo `purchase_catalog_coupon` (que insertaba en transactions
-- y representaba el pago) por uno que sólo:
--   - Decrementa stock de forma atómica (UPDATE ... RETURNING).
--   - Inserta el lead en `coupon_leads` (sólo email para el catálogo).
--   - Devuelve los datos que necesita la Edge Function para el correo.
-- =====================================================================

-- 0. Limpieza por si una versión previa con pagos quedó aplicada localmente.
DROP FUNCTION IF EXISTS public.purchase_catalog_coupon(uuid, text, text, numeric, text);

-- 1. El catálogo sólo captura email, así que relajamos las columnas
--    obligatorias del flujo flash para poder reusar la misma tabla
--    como bitácora unificada de leads.
ALTER TABLE public.coupon_leads
  ALTER COLUMN first_name  DROP NOT NULL,
  ALTER COLUMN last_name   DROP NOT NULL,
  ALTER COLUMN id_document DROP NOT NULL;

-- 2. RPC de canje del catálogo.
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
  -- Decremento atómico. A diferencia del flash, no exigimos
  -- is_popup_active: el catálogo expone TODOS los cupones vigentes.
  UPDATE public.coupons
     SET amount_available = amount_available - 1
   WHERE id = p_coupon_id
     AND amount_available > 0
     AND (end_date IS NULL OR end_date > now())
   RETURNING amount_available, code, title, image_url, end_date
        INTO v_remaining, v_code, v_title, v_image, v_end_date;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COUPON_UNAVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  -- Lead con email; si el mismo correo ya reclamó este cupón, devolvemos
  -- el stock para no penalizar al usuario por un reintento.
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
