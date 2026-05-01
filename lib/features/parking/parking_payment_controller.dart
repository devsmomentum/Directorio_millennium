import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Indica si hay un pago en curso (WebView abierta o esperando confirmación)
  bool _isPaymentInProgress = false;

  /// Suscripción Realtime para detectar cambios en parking_tickets
  RealtimeChannel? _ticketChannel;

  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  ParkingTicketDetails? get ticket => _ticket;
  ParkingPaymentOrder? get lastOrder => _lastOrder;
  String? get error => _error;
  bool get isPaymentInProgress => _isPaymentInProgress;

  @override
  void dispose() {
    _unsubscribeRealtime();
    super.dispose();
  }

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
    _isPaymentInProgress = false;
    _unsubscribeRealtime();
    notifyListeners();

    try {
      final normalized = trimmed.toUpperCase();
      debugPrint('[ParkingPayment] verifyTicket request barcode=$normalized');
      _ticket = await _service.verifyTicket(normalized);
      debugPrint(
        '[ParkingPayment] verifyTicket ok status=${_ticket!.status} amount=${_ticket!.amount}',
      );

      // Si el ticket ya está pagado (podría haber sido pagado vía webhook
      // mientras el usuario perdió conexión), lo mostramos directamente
      if (_ticket!.status == ParkingTicketStatus.paid) {
        debugPrint('[ParkingPayment] Ticket ya está pagado. No se requiere acción.');
      }

      // Iniciar listener Realtime para detectar cambios de estado
      // (útil si el pago se completa server-side vía webhook)
      _subscribeRealtime(normalized);
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
    _isPaymentInProgress = false;
    _unsubscribeRealtime();
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
    _isPaymentInProgress = true;
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
      _isPaymentInProgress = false;
      _setError(_messageFromException(error), clearTicket: false);
      return null;
    }
  }

  /// Marca que el flujo de pago ha terminado (WebView cerrada, etc.)
  void markPaymentFlowEnded() {
    _isPaymentInProgress = false;
    notifyListeners();
  }

  Future<bool> simulatePayment() async {
    final ticket = _ticket;
    if (ticket == null) {
      _setError('No hay ticket para procesar.');
      return false;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      await _service.simulatePayment(ticket.barcode);
      
      // Actualizamos el ticket localmente para reflejar el cambio en la UI
      _ticket = ParkingTicketDetails(
        barcode: ticket.barcode,
        status: ParkingTicketStatus.paid,
        amount: ticket.amount,
      );
      
      _isSubmitting = false;
      _isPaymentInProgress = false;
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('[ParkingPayment] simulatePayment error: $error');
      _setError(_messageFromException(error), clearTicket: false);
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Realtime: escuchar cambios en parking_tickets para este barcode
  // ──────────────────────────────────────────────────────────────────

  void _subscribeRealtime(String barcode) {
    _unsubscribeRealtime();

    debugPrint('[ParkingPayment] Subscribing to Realtime for barcode=$barcode');

    _ticketChannel = Supabase.instance.client
        .channel('parking-ticket-$barcode')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'parking_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'barcode',
            value: barcode,
          ),
          callback: (payload) {
            debugPrint('[ParkingPayment] Realtime UPDATE received: ${payload.newRecord}');
            _handleRealtimeUpdate(payload.newRecord, barcode);
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[ParkingPayment] Realtime channel status: $status');
          if (error != null) {
            debugPrint('[ParkingPayment] Realtime channel error: $error');
          }
        });
  }

  void _unsubscribeRealtime() {
    if (_ticketChannel != null) {
      debugPrint('[ParkingPayment] Unsubscribing from Realtime');
      Supabase.instance.client.removeChannel(_ticketChannel!);
      _ticketChannel = null;
    }
  }

  void _handleRealtimeUpdate(Map<String, dynamic> newRecord, String barcode) {
    final newStatus = parkingTicketStatusFrom(newRecord['status']?.toString());

    // Si el ticket pasó a 'paid', actualizar la UI automáticamente
    if (newStatus == ParkingTicketStatus.paid && _ticket != null) {
      debugPrint('[ParkingPayment] 🎉 Pago confirmado via Realtime para barcode=$barcode');

      _ticket = ParkingTicketDetails(
        barcode: _ticket!.barcode,
        status: ParkingTicketStatus.paid,
        amount: _ticket!.amount,
        exitCode: newRecord['exit_code']?.toString(),
      );

      _isSubmitting = false;
      _isPaymentInProgress = false;
      _error = null;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────────

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
