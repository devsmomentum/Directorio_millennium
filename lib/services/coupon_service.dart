import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/flash_coupon.dart';

class ClaimPayload {
  final String couponId;
  final String firstName;
  final String lastName;
  final String idDocument;
  final String email;

  const ClaimPayload({
    required this.couponId,
    required this.firstName,
    required this.lastName,
    required this.idDocument,
    required this.email,
  });

  Map<String, dynamic> toJson() => {
        'coupon_id': couponId,
        'first_name': firstName,
        'last_name': lastName,
        'id_document': idDocument,
        'email': email,
      };
}

class CouponService {
  CouponService._();
  static final CouponService instance = CouponService._();

  final SupabaseClient _client = Supabase.instance.client;

  /// Trae un cupón flash aleatorio entre todos los activos con
  /// `plan_type = 'PUBLI_PROMO'`, stock disponible y `end_date` futura.
  /// Si se pasa [excludeId] y hay más de un cupón, excluye ese ID para
  /// garantizar rotación entre sesiones.
  Future<FlashCoupon?> fetchActiveFlashCoupon({String? excludeId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await _client
        .from('coupons')
        .select()
        .eq('plan_type', 'PUBLI_PROMO')
        .gt('amount_available', 0)
        .gt('end_date', nowIso);

    if (rows.isEmpty) return null;
    var list = List<Map<String, dynamic>>.from(rows);

    if (list.length > 1 && excludeId != null) {
      final filtered = list.where((r) => r['id'] != excludeId).toList();
      if (filtered.isNotEmpty) list = filtered;
    }

    list.shuffle(Random());
    return FlashCoupon.fromJson(list.first);
  }

  Future<void> claimCoupon(ClaimPayload payload) async {
    final response = await _client.functions.invoke(
      'claim-flash-coupon',
      body: payload.toJson(),
    );

    final status = response.status;
    if (status >= 400) {
      throw ClaimCouponException.fromResponse(status, response.data);
    }
  }

  /// Reclama un cupón del catálogo (sin pago, sólo correo).
  /// Decrementa stock atómicamente y envía el código de canjeo por SMTP.
  Future<void> claimCatalogCoupon({
    required String couponId,
    required String email,
  }) async {
    final response = await _client.functions.invoke(
      'claim-catalog-coupon',
      body: {'coupon_id': couponId, 'email': email},
    );

    final status = response.status;
    if (status >= 400) {
      throw ClaimCouponException.fromResponse(status, response.data);
    }
  }
}

/// Error tipado para distinguir los casos que el Edge Function devuelve.
class ClaimCouponException implements Exception {
  final int status;
  final String code;
  final String message;

  const ClaimCouponException({
    required this.status,
    required this.code,
    required this.message,
  });

  factory ClaimCouponException.fromResponse(int status, dynamic data) {
    final code = (data is Map && data['error'] is String)
        ? data['error'] as String
        : 'unknown';
    return ClaimCouponException(
      status: status,
      code: code,
      message: _messageFor(code, status),
    );
  }

  static String _messageFor(String code, int status) {
    switch (code) {
      case 'coupon_unavailable':
        return 'El cupón ya no está disponible o ha expirado.';
      case 'lead_duplicate':
        return 'Ya reclamaste este cupón con este correo.';
      case 'invalid_email':
        return 'El correo ingresado no es válido.';
      case 'missing_fields':
        return 'Faltan datos en el formulario.';
      case 'smtp_send_failed':
        return 'Tu cupón fue reservado, pero no pudimos enviar el correo. '
            'Contáctanos para reenviarlo.';
      default:
        return 'No se pudo reclamar el cupón (status: $status).';
    }
  }

  @override
  String toString() => message;
}
