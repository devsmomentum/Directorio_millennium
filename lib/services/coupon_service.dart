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

  /// Trae el cupón con `is_popup_active = true` y stock disponible.
  /// Filtramos `end_date` del lado del cliente para tolerar registros sin fecha.
  Future<FlashCoupon?> fetchActiveFlashCoupon() async {
    final rows = await _client
        .from('coupons')
        .select()
        .eq('is_popup_active', true)
        .gt('amount_available', 0)
        .order('created_at', ascending: false)
        .limit(5);

    final now = DateTime.now();
    for (final row in rows) {
      final coupon = FlashCoupon.fromJson(row);
      final notExpired = coupon.endDate == null || coupon.endDate!.isAfter(now);
      if (notExpired) return coupon;
    }
    return null;
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
