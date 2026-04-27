# Auditoría del Sistema de Cupones — Milemium

> Informe técnico del estado actual del módulo de cupones de la app de kiosko Milemium.
> Cubre base de datos, Edge Function, servicio Flutter, widgets y flujos de usuario.
> Pensado como guía de onboarding para cualquier desarrollador que vaya a tocar este módulo.

---

## 1. Resumen ejecutivo

Hoy en la aplicación coexisten **dos flujos paralelos de cupón** que comparten la misma tabla
`public.coupons` y **el mismo patrón de canje atómico vía RPC + Edge Function SMTP**.
Ningún flujo cobra: ambos son canjes gratuitos; el código se entrega por correo.

| Flujo | Punto de entrada | Filtro | Datos que captura | Edge Function | RPC |
|-------|------------------|--------|-------------------|---------------|-----|
| **Flash Coupon (pop-up)** | `HomeScreen` al cargar | `coupons` con `is_popup_active = true` | Nombre, Apellidos, Cédula, Email | `claim-flash-coupon` | `claim_flash_coupon` |
| **Cupones / Ofertas (catálogo)** | Pestaña "Cupones" del bottom nav | `coupons` (todos los registros) | Email | `claim-catalog-coupon` | `claim_catalog_coupon` |

**Tablas relacionadas:** `public.coupons` (catálogo) y `public.coupon_leads` (bitácora unificada
de canjes — flash y catálogo). `public.transactions` ya **no** se usa para cupones (no hay pago).

---

## 2. Esquema de base de datos

### 2.1 `public.coupons` — catálogo único de cupones

Definido en `schema.sql:64-82`. Campos relevantes:

| Campo | Tipo | Uso |
|-------|------|-----|
| `id` | uuid PK | Identificador del cupón |
| `store_id` | uuid FK → `stores` | Tienda dueña del cupón |
| `image_url` | text | Imagen mostrada en card y popup |
| `code` | text UNIQUE | Código de canje (también payload del QR) |
| `amount_available` | integer (def. 0) | Stock disponible — se decrementa al canjear |
| `title` | text (def. `'Cupón Promocional'`) | Título visible |
| `price_usd` | numeric (def. 0.00) | Precio en USD; se convierte a Bs con tasa BCV |
| `campaign_id` | uuid FK → `ad_campaigns` | Campaña publicitaria asociada |
| `is_popup_active` | boolean (def. false) | **Bandera clave**: si es `true`, el cupón es candidato a aparecer como Flash Coupon en `HomeScreen` |
| `plan_type` | text CHECK | `'DIAMANTE' \| 'ORO' \| 'IA_PERFORMANCE' \| 'BONO_PREMIADO'` |
| `start_date`, `end_date` | timestamptz | Vigencia. `end_date` se valida en RPC y en el cliente |
| `category` | text | Categoría libre (no FK a `categories`) |

### 2.2 `public.coupon_leads` — leads de canjes (flash y catálogo)

Definido en `supabase/migrations/20260425120000_flash_coupon_leads.sql:7-26`. La migración
`20260426120000_claim_catalog_coupon.sql` relaja `first_name/last_name/id_document` a `NULL`
para que el flujo catálogo (que sólo captura email) reuse la misma tabla.

| Campo | Tipo | Uso |
|-------|------|-----|
| `id` | uuid PK | |
| `coupon_id` | uuid FK → `coupons` ON DELETE CASCADE | Cupón reclamado |
| `first_name`, `last_name`, `id_document` | text NULL | Sólo se llenan en el flujo flash |
| `email` | text NOT NULL | Único campo obligatorio (común a ambos flujos) |
| `email_sent_at` | timestamptz | Marca cuándo la Edge Function envió el correo (best-effort) |
| `created_at` | timestamptz | |

**Restricciones importantes:**
- `CHECK` de formato de email (regex).
- **Índice único `coupon_leads_unique_per_coupon` sobre `(coupon_id, lower(email))`** → un mismo correo no puede reclamar el mismo cupón flash dos veces.
- **RLS habilitado y sin políticas** (línea 29): la tabla está cerrada a accesos directos. El único camino de escritura es la RPC `claim_flash_coupon` con `SECURITY DEFINER`.

### 2.3 `public.transactions` — registro financiero (no se usa para cupones)

Definida en `schema.sql:183-196`. **Los cupones ya no escriben aquí**: ni el flujo catálogo
ni el flash. Ambos son canjes gratuitos. La tabla queda reservada para flujos transaccionales
reales (servicios, recargas, etc.).

---

## 3. Edge Functions de canje

Hay **dos** Edge Functions, una por flujo, con el mismo patrón:
RPC atómica → SMTP → marcar `email_sent_at`.

- `supabase/functions/claim-flash-coupon/index.ts` — flujo flash (pop-up): payload con
  Nombre, Apellidos, Cédula y Email. Llama a la RPC `claim_flash_coupon` (exige
  `is_popup_active = true`).
- `supabase/functions/claim-catalog-coupon/index.ts` — flujo catálogo (pestaña Cupones):
  payload sólo con Email. Llama a la RPC `claim_catalog_coupon` (sin la guarda
  `is_popup_active`, abierta a todo el catálogo).

A continuación se documenta `claim-flash-coupon`; el catálogo es estructuralmente idéntico,
salvo que su RPC inserta en `coupon_leads` con sólo el email y no requiere
`is_popup_active`.

### 3.0 `claim-flash-coupon`

Archivo: `supabase/functions/claim-flash-coupon/index.ts`.

### 3.1 Responsabilidades
1. Validar payload (`coupon_id`, `first_name`, `last_name`, `id_document`, `email`).
2. Llamar a la RPC atómica `claim_flash_coupon` (Supabase con `SUPABASE_SERVICE_ROLE_KEY`).
3. Construir y enviar correo SMTP con HTML + texto plano (cliente `denomailer`).
4. Marcar `coupon_leads.email_sent_at` (best-effort; no revierte si falla).

### 3.2 Variables de entorno requeridas
`SMTP_HOST`, `SMTP_PORT` (587 STARTTLS / 465 TLS), `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`.
`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` se inyectan automáticamente.

### 3.3 Códigos de error devueltos
| HTTP | `error` | Significado |
|------|---------|-------------|
| 400 | `invalid_json` / `missing_fields` / `invalid_email` | Validación cliente |
| 409 | `coupon_unavailable` | Sin stock, inactivo, vencido o inexistente |
| 409 | `lead_duplicate` | Ese correo ya reclamó este cupón |
| 500 | `rpc_failed` / `rpc_empty` / `smtp_misconfigured` | Errores internos |
| 502 | `smtp_send_failed` | El lead se grabó pero el correo falló |

### 3.4 RPC `claim_flash_coupon` (atómico)
Definida en la misma migración (`...flash_coupon_leads.sql:41-105`). Pasos:
1. `UPDATE coupons SET amount_available = amount_available - 1 WHERE id = ? AND is_popup_active AND amount_available > 0 AND (end_date IS NULL OR end_date > now()) RETURNING ...`
   → Si no actualiza, lanza `COUPON_UNAVAILABLE`.
2. `INSERT INTO coupon_leads ...`
   → Si viola el índice único, **revierte el decremento** (`+1`) y lanza `LEAD_DUPLICATE`.
3. Retorna `lead_id`, datos del cupón y `remaining` para que la Edge Function arme el correo.

`SECURITY DEFINER` + `REVOKE ALL` + `GRANT EXECUTE TO anon, authenticated, service_role` — la única forma de tocar `coupon_leads` desde fuera es esta RPC.

---

## 4. Capas Flutter

### 4.1 Modelo — `lib/models/flash_coupon.dart`
DTO inmutable que mapea filas de `coupons`. Helper `qrPayload` cae a `id` si `code` es nulo.

### 4.2 Servicio — `lib/services/coupon_service.dart`
Singleton `CouponService.instance`. Dos métodos:

- **`fetchActiveFlashCoupon()`** — `coupons.select().eq('is_popup_active', true).gt('amount_available', 0).order('created_at desc').limit(5)`. Filtra `end_date` en cliente y devuelve el primero que no haya vencido. Si no hay candidatos, retorna `null`.
- **`claimCoupon(ClaimPayload)`** — invoca la Edge Function `claim-flash-coupon`. Si `status >= 400`, lanza `ClaimCouponException` con mensaje localizado en español según el `error` devuelto.

### 4.3 Widgets

| Widget | Archivo | Rol |
|--------|---------|-----|
| `FlashCouponDialog` | `lib/widgets/flash_coupon_dialog.dart` | Pop-up del Flash Coupon: imagen, título, precio, QR, contador 20s, escasez (`_ScarcityBanner`), botón "Reclamar" |
| `ClaimCouponForm` | `lib/widgets/claim_coupon_form.dart` | Formulario full-screen (Nombre, Apellidos, Cédula, Correo). Llama a `CouponService.claimCoupon` |
| `CouponsScreen` | `lib/screens/coupons_screen.dart` | Pantalla de catálogo de cupones (pestaña 4). Realtime sobre `public:coupons`. Modal QR + modal de email |

### 4.4 Pantallas que orquestan

- **`HomeScreen`** (`lib/screens/home_screen.dart:32-54`):
  flag local `_flashCouponShown`; en `addPostFrameCallback` llama `_maybeShowFlashCoupon()` **una sola vez por instancia** (no se repite hasta volver a montar la pantalla).
- **`MainLayout`** (`lib/screens/main_layout.dart:46`):
  registra `CouponsScreen` como índice 4 del `IndexedStack`. Botón en el bottom nav (`_buildNavItem(Icons.local_activity_outlined, 'Cupones', 4)`, línea 321). Subtítulo del header: `'CUPONES Y OFERTAS'`.

---

## 5. Flujos de usuario

### 5.1 Flujo A — Flash Coupon (pop-up promocional)

```
1. Kiosko entra al HomeScreen (pantalla inicial / video loop publicitario).
2. Tras el primer frame:                          HomeScreen._maybeShowFlashCoupon
   └─ CouponService.fetchActiveFlashCoupon
      └─ SELECT coupons WHERE is_popup_active=TRUE AND amount_available>0 (limit 5, filtrado de end_date en cliente)
3. Si hay un candidato → muestra FlashCouponDialog (modal NO descartable, barrier=false).
   - Imagen + título + precio USD + QR (payload: code ?? id).
   - Contador regresivo de 20 s con CircularProgressIndicator.
   - "_ScarcityBanner" rojo si quedan ≤10 unidades.
   - Botón "Reclamar cupón":
        a. Cancela el ticker (la urgencia ya cumplió).
        b. Empuja ClaimCouponForm como ruta full-screen.
4. Usuario llena Nombre/Apellidos/Cédula/Email → submit:
   └─ CouponService.claimCoupon → Supabase Functions invoke('claim-flash-coupon')
      └─ Edge Function → RPC claim_flash_coupon (decrementa stock + inserta lead, atómico)
      └─ SMTP envía correo con código + fecha de vencimiento + remaining.
      └─ UPDATE coupon_leads.email_sent_at = now().
5. SnackBar "¡Cupón enviado a tu correo! Revisa tu bandeja." → Navigator.pop(true) → cierra el dialog.
   - Si falla el correo: cupón ya está reservado, lead grabado; el usuario ve un SnackBar rojo
     y _puede_ reintentar (devolverá `lead_duplicate` y la RPC NO descontará stock).
```

**Frecuencia:** una sola vez por montaje de `HomeScreen`. Si el kiosko vuelve al Home tras un timeout (60 s de inactividad en `MainLayout`) y se desmonta/remonta el árbol, el pop-up vuelve a evaluarse. Mientras `HomeScreen` siga vivo, no se vuelve a mostrar.

**Cuál se muestra:** el más recientemente creado (`order created_at desc`) que cumpla los tres filtros: `is_popup_active`, stock > 0, no vencido. Sólo uno a la vez.

### 5.2 Flujo B — Catálogo de cupones (pestaña "Cupones")

```
1. Usuario toca "Cupones" en el bottom nav (índice 4) → CouponsScreen.
2. _fetchCoupons:
   - SELECT coupons.*, stores(name) ORDER BY created_at DESC.
   - Suscripción Realtime al canal 'public:coupons' → refetch al detectar cualquier evento.
3. GridView 3 columnas con _buildCouponCard:
   - Imagen, badge STOCK, badge "GRATIS".
   - Si amount_available <= 0 → overlay "AGOTADO".
4. Tap en card disponible → _showClaimModal:
   - Muestra título + tienda + campo Email + botón "RECLAMAR CUPÓN".
   - No hay paso intermedio de pago/QR: el catálogo es canje directo.
5. Submit de "RECLAMAR CUPÓN":
   └─ CouponService.claimCatalogCoupon → Supabase Functions invoke('claim-catalog-coupon')
      └─ Edge Function → RPC claim_catalog_coupon
          (decrementa stock atómicamente + inserta lead con email, en una sola TX)
      └─ SMTP envía correo con código de canjeo + fecha de vencimiento + remaining.
      └─ UPDATE coupon_leads.email_sent_at = now().
   - SnackBar verde de éxito.
   - Si el correo falla: stock decrementado y lead grabado; se muestra SnackBar rojo
     y se puede reintentar (devuelve `lead_duplicate` y la RPC NO descontará stock dos veces).
```

**Cuáles se muestran:** todos los cupones de la tabla, ordenados por `created_at desc`. Los agotados se ven con overlay rojo "AGOTADO" y no son tappables.
**Frecuencia:** cada vez que el usuario entra a la pestaña; además se actualiza en vivo vía Postgres Changes.

---

## 6. Diferencias y mito de las "dos tablas de cupones"

**No existen dos tablas de cupones.** Existe **una sola tabla** `public.coupons` que sirve a los dos flujos, y una tabla auxiliar `public.coupon_leads` que **no contiene cupones**, sino los registros de quién reclamó qué cupón flash (lead capture).

| `coupons` | `coupon_leads` |
|-----------|----------------|
| Catálogo maestro de cupones (definición, stock, precio, vigencia) | Bitácora de leads capturados al reclamar un cupón flash |
| Una fila = un cupón disponible para los kioskos | Una fila = un usuario que rellenó el formulario flash |
| La consume `CouponsScreen`, `FlashCouponDialog` y la RPC | Sólo la escribe la RPC `claim_flash_coupon` (RLS cerrado) |
| Sin RLS efectivo (lectura abierta para `anon`) | RLS habilitado sin políticas: bloqueada al cliente |

### ¿Es viable colapsarlas a una sola tabla?
**No, y no es lo que se debería hacer.** Son entidades distintas:
- `coupons` = **producto** (qué se ofrece).
- `coupon_leads` = **eventos de adquisición** (quién lo tomó y cuándo).
Mezclarlas duplicaría la fila del cupón por cada lead y rompería la unicidad de `code`. La separación actual es la modelación correcta (es básicamente la pareja "producto / pedido").

### Unificación de la lógica de canje (ya hecho)
Ambos flujos usan hoy el **mismo patrón**: RPC `SECURITY DEFINER` con decremento atómico
(`UPDATE ... WHERE amount_available > 0 RETURNING ...`) + inserción del lead en la misma
transacción SQL + envío SMTP desde Edge Function. La race condition que tenía el catálogo
quedó cerrada al pasar de un `UPDATE` cliente-side a la RPC `claim_catalog_coupon`.

---

## 7. Inventario de widgets/pantallas que tocan cupones

| Archivo | Rol respecto a cupones |
|---------|------------------------|
| `lib/screens/home_screen.dart` | Dispara el pop-up flash al montarse |
| `lib/widgets/flash_coupon_dialog.dart` | Pop-up del flash (timer, QR, escasez) |
| `lib/widgets/claim_coupon_form.dart` | Formulario de captura de lead (nombre/apellido/cédula/email) |
| `lib/services/coupon_service.dart` | Único cliente de la tabla `coupons` y de la Edge Function |
| `lib/models/flash_coupon.dart` | DTO de cupón (subset de columnas que usa el flujo flash) |
| `lib/screens/coupons_screen.dart` | Pestaña catálogo: grid + modales QR y email + Realtime |
| `lib/screens/main_layout.dart` | Registra `CouponsScreen` en el `IndexedStack` (idx 4) y botón en bottom nav |
| `supabase/functions/claim-flash-coupon/index.ts` | Edge Function de canje flash + correo |
| `supabase/functions/claim-catalog-coupon/index.ts` | Edge Function de canje catálogo + correo |
| `supabase/migrations/20260425120000_flash_coupon_leads.sql` | DDL de `coupon_leads` y RPC `claim_flash_coupon` |
| `supabase/migrations/20260426120000_claim_catalog_coupon.sql` | RPC `claim_catalog_coupon` y relajado de `NOT NULL` en `coupon_leads` |
| `schema.sql` | Definición declarativa de `coupons` y `transactions` |

> **No tocan cupones** los archivos de mapa (`map_view_web.dart`, `map_view_post_msg_web.dart`); los matches del grep son sobre la palabra "flash" en otro contexto (flashes negros de render).

---

## 8. Sección "Cupones" — gestión actual

- **Punto de acceso**: bottom nav, ítem 3 (`Icons.local_activity_outlined`, índice lógico 4).
- **Estado**: `CouponsScreen` (StatefulWidget). Carga el catálogo de Supabase.
- **Tiempo real**: canal Postgres Changes `public:coupons` con `event: PostgresChangeEvent.all`. Cualquier `INSERT/UPDATE/DELETE` en la tabla refresca el grid.
- **Render**: `GridView.builder` 3×N, `childAspectRatio: 0.72`. Cards con stock y badge "GRATIS".
- **Interacción**: un solo modal — pide email y dispara el canje. No hay paso de pago/QR.
- **Persistencia del canje**: RPC `claim_catalog_coupon` (decremento atómico + lead) + Edge
  Function `claim-catalog-coupon` (correo SMTP con código de canjeo).
- **Limpieza**: el `RealtimeChannel` se libera en `dispose` con `_client.removeChannel`.

---

## 9. Hallazgos de auditoría (resumen accionable)

1. ~~**Race condition en el flujo catálogo**~~ → resuelto con RPC `claim_catalog_coupon`.
2. ~~**Privilegios de escritura desde el cliente** sobre `coupons`/`transactions`~~ → el catálogo
   ya no escribe directamente: pasa por RPC `SECURITY DEFINER`. Aún así, conviene endurecer
   el RLS de `coupons` para revocar el `UPDATE` directo desde `anon`.
3. ~~**Doble fuente de verdad de email**~~ → ambos flujos envían correo real vía SMTP.
4. **`is_popup_active` y `plan_type` no están relacionados**. La regla "qué es flash" hoy es sólo `is_popup_active`. Si el negocio quiere que `BONO_PREMIADO` sea el único tipo flash, conviene mover la regla al `plan_type` y eliminar la bandera, o al menos documentarla.
5. **Vencimiento filtrado en cliente** en `fetchActiveFlashCoupon`. Se podría mover a la query (`.gt('end_date', now)` con `or` para nulos) para no traer filas inútiles.
6. **`coupon_leads.id_document`** se almacena en texto plano sin validación de formato ni hashing (sólo aplica al flujo flash; el catálogo no captura cédula). Verificar requisitos legales (LOPD/LSSI equivalente local) antes de seguir capturándolo.
7. **El pop-up flash sólo se evalúa una vez por montaje de `HomeScreen`** — si el kiosko nunca vuelve al Home, no se ofrece otro cupón aunque salga uno nuevo. Considerar poll periódico o señal Realtime.
8. **Sin telemetría**: `analytics_events` existe pero no se inserta nada cuando un cupón se muestra/cierra/reclama. Útil para medir conversión.

---

## 10. Cómo intervenir el módulo (cheat-sheet)

- **Cambiar el contenido del correo**: `supabase/functions/claim-flash-coupon/index.ts:65-121` (`buildEmail`).
- **Cambiar el countdown del pop-up**: parámetro `countdown` de `FlashCouponDialog` (default 20 s, `flash_coupon_dialog.dart:15`).
- **Cambiar el umbral de "escasez"**: `_ScarcityBanner.critical = remaining <= 10` (`flash_coupon_dialog.dart:221`).
- **Activar/desactivar un flash**: en BD, `UPDATE coupons SET is_popup_active = TRUE WHERE id = ...` y asegurar `amount_available > 0` y `end_date` futura.
- **Forzar el pop-up en debug**: tocar `_flashCouponShown = false` en `home_screen.dart:32` o llamar `_maybeShowFlashCoupon` desde un botón.
- **Probar la Edge Function localmente**: `supabase functions serve claim-flash-coupon --env-file .env.local` y llamarla con `curl` simulando el payload de `ClaimPayload.toJson()`.
- **Reset de stock tras pruebas**: `UPDATE coupons SET amount_available = X WHERE id = ...`; los leads pueden purgarse con `DELETE FROM coupon_leads WHERE coupon_id = ...` (hay `ON DELETE CASCADE` desde `coupons`, así que borrar el cupón también borra sus leads).

---

*Documento generado como auditoría de estado actual; no introduce cambios de código.*
