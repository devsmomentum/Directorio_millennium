import 'package:flutter/material.dart';

import 'parking_payment_models.dart';
import 'parking_payment_service.dart';

class ParkingPaymentController extends ChangeNotifier {
  ParkingPaymentController({ParkingPaymentService? service})
      : _service = service ?? ParkingPaymentService();

  final ParkingPaymentService _service;

  bool _isLoading = false;
  bool _isSubmitting = false;
  ParkingTicketDetails? _ticket;
  ParkingPaymentOrder? _lastOrder;
  String? _error;

  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  ParkingTicketDetails? get ticket => _ticket;
  ParkingPaymentOrder? get lastOrder => _lastOrder;
  String? get error => _error;

  Future<void> searchTicket(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _setError('Ingresa el codigo del ticket.');
      return;
    }

    debugPrint('[ParkingPayment] searchTicket start codeLen=${trimmed.length}');
    _isLoading = true;
    _error = null;
    _ticket = null;
    _lastOrder = null;
    notifyListeners();

    try {
      final normalized = trimmed.toUpperCase();
      debugPrint('[ParkingPayment] verifyTicket request barcode=$normalized');
      _ticket = await _service.verifyTicket(normalized);
      debugPrint(
        '[ParkingPayment] verifyTicket ok status=${_ticket!.status} amount=${_ticket!.amount}',
      );
    } catch (error) {
      debugPrint('[ParkingPayment] verifyTicket error: $error');
      _setError(_messageFromException(error));
      return;
    }

    _isLoading = false;
    notifyListeners();
  }

  void clearTicket() {
    _ticket = null;
    _error = null;
    _lastOrder = null;
    notifyListeners();
  }

  Future<ParkingPaymentOrder?> createPaymentOrder() async {
    final ticket = _ticket;
    if (ticket == null) {
      _setError('No hay ticket para procesar.');
      return null;
    }

    debugPrint(
      '[ParkingPayment] createPaymentOrder start barcode=${ticket.barcode} amount=${ticket.amount}',
    );
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final order = await _service.createPaymentOrder(
        barcode: ticket.barcode,
        amount: ticket.amount,
      );
      _lastOrder = order;
      debugPrint(
        '[ParkingPayment] createPaymentOrder ok orderId=${order.orderId} status=${order.status}',
      );
      _isSubmitting = false;
      notifyListeners();
      return order;
    } catch (error) {
      debugPrint('[ParkingPayment] createPaymentOrder error: $error');
      _setError(_messageFromException(error), clearTicket: false);
      return null;
    }
  }

  String formatCurrency(num value, {String symbol = '\$'}) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final fracPart = parts[1];

    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final position = intPart.length - i;
      buffer.write(intPart[i]);
      if (position > 1 && position % 3 == 1) {
        buffer.write(',');
      }
    }

    return '$symbol${buffer.toString()}.$fracPart';
  }

  void _setError(String message, {bool clearTicket = true}) {
    _error = message;
    if (clearTicket) {
      _ticket = null;
    }
    _isLoading = false;
    _isSubmitting = false;
    notifyListeners();
  }

  String _messageFromException(Object error) {
    if (error is ParkingPaymentException) return error.message;
    debugPrint('[ParkingPayment] unknown error type: ${error.runtimeType}');
    return 'No se pudo completar la operacion.';
  }
}
