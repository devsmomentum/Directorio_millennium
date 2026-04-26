/// Mapea la tabla `public.coupons` (ver schema.sql).
class FlashCoupon {
  final String id;
  final String title;
  final String? code;
  final String? imageUrl;
  final int amountAvailable;
  final double priceUsd;
  final DateTime? endDate;
  final String? storeId;

  const FlashCoupon({
    required this.id,
    required this.title,
    required this.amountAvailable,
    required this.priceUsd,
    this.code,
    this.imageUrl,
    this.endDate,
    this.storeId,
  });

  /// Payload que se incrusta en el QR (no redirige todavía;
  /// usamos `code` cuando exista por ser único, y caemos al `id`).
  String get qrPayload => code ?? id;

  factory FlashCoupon.fromJson(Map<String, dynamic> json) {
    return FlashCoupon(
      id: json['id'].toString(),
      title: (json['title'] as String?) ?? 'Cupón Promocional',
      code: json['code'] as String?,
      imageUrl: json['image_url'] as String?,
      amountAvailable: (json['amount_available'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble() ?? 0.0,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'].toString())
          : null,
      storeId: json['store_id']?.toString(),
    );
  }
}
