-- Seed de 10 cupones demo para las tiendas:
--   BONSAI SUSHI       (DIAMANTE / Comida rápida)
--   BANCO EXTERIOR     (DIAMANTE / Servicios)
--   CAMII HOGAR        (ORO / Muebles y accesorios para el hogar)
--   TIENDA PADEL       (IA_PERFORMANCE / Artículos deportivos)
--
-- Modelo (post-migración 20260427120000_coupons_publi_promo.sql):
--   * La columna `is_popup_active` ya NO existe.
--   * Los cupones flash (pop-up) son los que tienen `plan_type = 'PUBLI_PROMO'`.
--   * `end_date` es NOT NULL: TODO cupón debe declarar fecha límite.
--   * Canje gratuito (price_usd = 0); el código se entrega por correo
--     vía las RPC claim_flash_coupon / claim_catalog_coupon.
--
-- Distribución:
--   * 3 cupones con plan_type = 'PUBLI_PROMO' (alimentan FlashCouponDialog)
--   * 7 cupones con el plan comercial de la tienda (sólo en CouponsScreen)
--
-- Idempotente vía ON CONFLICT (code).

INSERT INTO public.coupons (
  store_id, image_url, code, amount_available, title,
  price_usd, plan_type, start_date, end_date, category
) VALUES
  -- ───────────── BONSAI SUSHI ─────────────
  ('1aa57206-5b02-4344-9db3-7a1953ce7d92',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300208399.png',
   'BONSAI-2X1-CALIFORNIA', 50, '2x1 en Roll California',
   0.00, 'PUBLI_PROMO', now(), '2026-05-31 23:59:59+00', 'Comida rápida'),

  ('1aa57206-5b02-4344-9db3-7a1953ce7d92',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300208399.png',
   'BONSAI-COMBO-FAMILIAR-30', 100, '30% OFF Combo Familiar',
   0.00, 'DIAMANTE',    now(), '2026-06-30 23:59:59+00', 'Comida rápida'),

  ('1aa57206-5b02-4344-9db3-7a1953ce7d92',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300208399.png',
   'BONSAI-BEBIDA-GRATIS', 200, 'Bebida gratis con cualquier roll',
   0.00, 'DIAMANTE',    now(), '2026-05-15 23:59:59+00', 'Comida rápida'),

  -- ───────────── BANCO EXTERIOR ─────────────
  ('34acb287-a5bb-4c23-a11a-2053bb808971',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774021598041.jpg',
   'BEXT-APERTURA-CUENTA', 30, 'Apertura de cuenta sin comisión',
   0.00, 'DIAMANTE',    now(), '2026-07-31 23:59:59+00', 'Servicios'),

  ('34acb287-a5bb-4c23-a11a-2053bb808971',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774021598041.jpg',
   'BEXT-TC-SIN-ANUALIDAD', 25, 'Tarjeta de crédito sin anualidad por 1 año',
   0.00, 'PUBLI_PROMO', now(), '2026-06-30 23:59:59+00', 'Servicios'),

  -- ───────────── CAMII HOGAR ─────────────
  ('62e9e5ca-960f-4d76-9967-5f59b166581a',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300300593.jpg',
   'CAMII-SALA-20OFF', 15, '20% OFF en juegos de sala',
   0.00, 'ORO',         now(), '2026-06-15 23:59:59+00', 'Muebles y accesorios para el hogar'),

  ('62e9e5ca-960f-4d76-9967-5f59b166581a',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300300593.jpg',
   'CAMII-ALMOHADAS-2X1', 80, 'Almohadas premium 2x1',
   0.00, 'ORO',         now(), '2026-05-30 23:59:59+00', 'Muebles y accesorios para el hogar'),

  -- ───────────── TIENDA PADEL ─────────────
  ('96e8d71f-ad72-4ac2-83cc-9c80d0c32598',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300007488.jpg',
   'PADEL-RAQUETA-10OFF', 40, '10% OFF en raquetas seleccionadas',
   0.00, 'IA_PERFORMANCE', now(), '2026-06-30 23:59:59+00', 'Artículos deportivos'),

  ('96e8d71f-ad72-4ac2-83cc-9c80d0c32598',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300007488.jpg',
   'PADEL-PELOTAS-3X2', 60, 'Pelotas Head 3x2',
   0.00, 'PUBLI_PROMO',    now(), '2026-05-31 23:59:59+00', 'Artículos deportivos'),

  ('96e8d71f-ad72-4ac2-83cc-9c80d0c32598',
   'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/publicidad/logos/logo_1774300007488.jpg',
   'PADEL-GRIP-GRATIS', 120, 'Grip gratis con la compra de tu raqueta',
   0.00, 'IA_PERFORMANCE', now(), '2026-06-15 23:59:59+00', 'Artículos deportivos')
ON CONFLICT (code) DO UPDATE SET
  store_id         = EXCLUDED.store_id,
  image_url        = EXCLUDED.image_url,
  amount_available = EXCLUDED.amount_available,
  title            = EXCLUDED.title,
  price_usd        = EXCLUDED.price_usd,
  plan_type        = EXCLUDED.plan_type,
  start_date       = EXCLUDED.start_date,
  end_date         = EXCLUDED.end_date,
  category         = EXCLUDED.category;
