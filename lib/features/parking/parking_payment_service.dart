import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/supabase_config.dart';
import 'parking_payment_models.dart';

class ParkingPaymentException implements Exception {
  final int status;
  final String message;

  const ParkingPaymentException({required this.status, required this.message});

  factory ParkingPaymentException.fromResponse(int status, dynamic data) {
    final message = _extractMessage(data) ?? 'Error de servidor ($status).';
    return ParkingPaymentException(status: status, message: message);
  }

  static String? _extractMessage(dynamic data) {
    if (data is Map) {
      if (data['message'] is String) return data['message'] as String;
      if (data['error'] is String) return data['error'] as String;
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return null;
  }

  @override
  String toString() => message;
}

class ParkingPaymentService {
  ParkingPaymentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _verifyTicketFunction = 'verify-ticket';
  static const String _createOrderFunction = 'create-order-parking-pap';

  Future<ParkingTicketDetails> verifyTicket(String barcode) async {
    final safeBarcode = barcode.length > 6
        ? '${barcode.substring(0, 3)}...${barcode.substring(barcode.length - 3)}'
        : barcode;
    print('[ParkingPayment][HTTP] verify-ticket -> barcode=$safeBarcode');
    final response = await _postJson(_verifyTicketFunction, {
      'barcode': barcode,
    });

    final data = _unwrapData(response);
    final status = parkingTicketStatusFrom(data['status']?.toString());
    final amount = _parseAmount(data['amount']);
    final serverBarcode = (data['barcode'] ?? barcode).toString().trim();

    return ParkingTicketDetails(
      barcode: serverBarcode.isEmpty ? barcode : serverBarcode,
      status: status,
      amount: amount,
    );
  }

  Future<ParkingPaymentOrder> createPaymentOrder({
    required String barcode,
    required double amount,
  }) async {
    const double amountBs = 10;
    final safeBarcode = barcode.length > 6
        ? '${barcode.substring(0, 3)}...${barcode.substring(barcode.length - 3)}'
        : barcode;
    print(
      '[ParkingPayment][HTTP] create-order-parking-pap -> barcode=$safeBarcode amount=$amountBs',
    );
    final response = await _postJson(_createOrderFunction, {
      'barcode': barcode,
      'amount': amountBs,
    });

    final data = _unwrapData(response);
    return ParkingPaymentOrder(
      orderId: (data['order_id'] ?? data['orderId'] ?? data['id'] ?? '')
          .toString(),
      urlPayment: (data['url_payment'] ??
              data['urlPayment'] ??
              data['payment_url'] ??
              '')
          .toString(),
      status: (data['status'] ?? 'pending').toString(),
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    print('[ParkingPayment][HTTP] POST $functionName bodyKeys=${body.keys.toList()}');
    final response = await _client.post(
      SupabaseConfig.functionUri(functionName),
      headers: _headers(),
      body: jsonEncode(body),
    );

    final decoded = _decodeResponse(response.body);
    print(
      '[ParkingPayment][HTTP] $functionName status=${response.statusCode} bodyType=${decoded.runtimeType}',
    );
    if (response.statusCode >= 400) {
      throw ParkingPaymentException.fromResponse(
        response.statusCode,
        decoded,
      );
    }

    return decoded;
  }

  Map<String, dynamic> _decodeResponse(String body) {
    if (body.trim().isEmpty) {
      print('[ParkingPayment][HTTP] empty response body');
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      print('[ParkingPayment][HTTP] response is not JSON');
      return <String, dynamic>{'message': body};
    }
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) return data;
    return payload;
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      'apikey': SupabaseConfig.anonKey,
      'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
    };
  }

  double _parseAmount(dynamic raw) {
    if (raw is num) return raw.toDouble();
    final parsed = double.tryParse(raw?.toString() ?? '');
    return parsed ?? 0.0;
  }
}
