enum ParkingTicketStatus {
  pending,
  paid,
  exited,
}

ParkingTicketStatus parkingTicketStatusFrom(String? value) {
  switch (value?.toLowerCase()) {
    case 'paid':
      return ParkingTicketStatus.paid;
    case 'exited':
      return ParkingTicketStatus.exited;
    case 'pending':
    default:
      return ParkingTicketStatus.pending;
  }
}

class ParkingTicketDetails {
  final String barcode;
  final ParkingTicketStatus status;
  final double amount;

  const ParkingTicketDetails({
    required this.barcode,
    required this.status,
    required this.amount,
  });

  String get statusLabel {
    switch (status) {
      case ParkingTicketStatus.pending:
        return 'Pendiente de pago';
      case ParkingTicketStatus.paid:
        return 'Pagado';
      case ParkingTicketStatus.exited:
        return 'Salido';
    }
  }
}

class ParkingPaymentOrder {
  final String orderId;
  final String urlPayment;
  final String status;

  const ParkingPaymentOrder({
    required this.orderId,
    required this.urlPayment,
    required this.status,
  });
}
