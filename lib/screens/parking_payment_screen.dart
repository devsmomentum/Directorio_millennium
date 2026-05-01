import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/parking/parking_payment_controller.dart';
import '../features/parking/parking_payment_models.dart';

class ParkingPaymentScreen extends StatelessWidget {
  const ParkingPaymentScreen({
    super.key,
    this.onBack,
    this.onOpenPaymentUrl,
    this.embedInLayout = false,
  });

  final VoidCallback? onBack;
  final ValueChanged<String>? onOpenPaymentUrl;
  final bool embedInLayout;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ParkingPaymentController(),
      child: ParkingPaymentView(
        onBack: onBack,
        onOpenPaymentUrl: onOpenPaymentUrl,
        embedInLayout: embedInLayout,
      ),
    );
  }
}

class ParkingPaymentView extends StatefulWidget {
  const ParkingPaymentView({
    super.key,
    this.onBack,
    this.onOpenPaymentUrl,
    this.embedInLayout = false,
  });

  final VoidCallback? onBack;
  final ValueChanged<String>? onOpenPaymentUrl;
  final bool embedInLayout;

  @override
  State<ParkingPaymentView> createState() => _ParkingPaymentViewState();
}

class _ParkingPaymentViewState extends State<ParkingPaymentView> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit(ParkingPaymentController controller) {
    FocusScope.of(context).unfocus();
    controller.searchTicket(_codeController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Consumer<ParkingPaymentController>(
        builder: (context, controller, _) {
          final ticket = controller.ticket;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onBack != null) ...[
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver a servicios'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Pago de estacionamiento',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ingresa el codigo del ticket para consultar el monto.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _TicketCodeInput(
                      controller: _codeController,
                      isLoading: controller.isLoading,
                      onSearch: () => _submit(controller),
                      onSubmitted: (_) => _submit(controller),
                    ),
                    const SizedBox(height: 16),
                    if (controller.isLoading)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          color: colorScheme.primary,
                          backgroundColor:
                              colorScheme.primary.withOpacity(0.2),
                        ),
                      ),
                    if (controller.error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: controller.error!),
                    ],
                    if (ticket != null) ...[
                      const SizedBox(height: 8),
                      _TicketDetailsCard(
                        ticket: ticket,
                        amountLabel: controller.formatCurrency(
                          ticket.amount,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: controller.isSubmitting ||
                                  ticket.status !=
                                      ParkingTicketStatus.pending
                              ? null
                              : () async {
                                  final order =
                                      await controller.createPaymentOrder();
                                  if (!mounted || order == null) return;
                                  final url = order.urlPayment.trim();
                                  if (url.isNotEmpty &&
                                      widget.onOpenPaymentUrl != null) {
                                    widget.onOpenPaymentUrl!(url);
                                    return;
                                  }
                                  final message = order.orderId.isNotEmpty
                                      ? 'Orden creada: ${order.orderId}'
                                      : 'Orden creada.';
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(message)),
                                  );
                                },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: controller.isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('Pagar'),
                        ),
                      ),
                      
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    if (widget.embedInLayout) {
      return content;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(child: content),
    );
  }
}

class _TicketCodeInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSearch;
  final ValueChanged<String> onSubmitted;

  const _TicketCodeInput({
    required this.controller,
    required this.isLoading,
    required this.onSearch,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
          ],
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            labelText: 'Codigo del ticket',
            hintText: 'Ej: A1B2C3',
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            filled: true,
            fillColor: colorScheme.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isLoading ? null : onSearch,
            icon: const Icon(Icons.search),
            label: const Text('Buscar'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketDetailsCard extends StatelessWidget {
  final ParkingTicketDetails ticket;
  final String amountLabel;

  const _TicketDetailsCard({
    required this.ticket,
    required this.amountLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColorFor(ticket.status, colorScheme);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalle del ticket',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            label: 'Codigo',
            value: Text(
              ticket.barcode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Estado',
            value: _StatusPill(
              label: ticket.statusLabel,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Total',
            value: Text(
              amountLabel,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: value,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColorFor(ParkingTicketStatus status, ColorScheme colorScheme) {
  switch (status) {
    case ParkingTicketStatus.pending:
      return colorScheme.primary;
    case ParkingTicketStatus.paid:
      return colorScheme.tertiary;
    case ParkingTicketStatus.exited:
      return colorScheme.outline;
  }
}
