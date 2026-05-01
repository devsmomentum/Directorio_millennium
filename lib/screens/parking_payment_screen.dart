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
    this.onPaymentConfirmed,
    this.embedInLayout = false,
  });

  final VoidCallback? onBack;
  final ValueChanged<String>? onOpenPaymentUrl;
  /// Se llama cuando el pago es confirmado (via Realtime/webhook),
  /// para que el padre cierre la WebView y muestre la confirmación.
  final VoidCallback? onPaymentConfirmed;
  final bool embedInLayout;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ParkingPaymentController(),
      child: ParkingPaymentView(
        onBack: onBack,
        onOpenPaymentUrl: onOpenPaymentUrl,
        onPaymentConfirmed: onPaymentConfirmed,
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
    this.onPaymentConfirmed,
    this.embedInLayout = false,
  });

  final VoidCallback? onBack;
  final ValueChanged<String>? onOpenPaymentUrl;
  final VoidCallback? onPaymentConfirmed;
  final bool embedInLayout;

  @override
  State<ParkingPaymentView> createState() => _ParkingPaymentViewState();
}

class _ParkingPaymentViewState extends State<ParkingPaymentView> {
  final TextEditingController _codeController = TextEditingController();
  ParkingPaymentController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ParkingPaymentController>();
    if (_controller != controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller!.addListener(_onControllerChanged);
    }
  }

  /// Detecta cuando el Realtime confirma el pago y notifica al padre
  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final ticket = controller.ticket;
    if (ticket != null && ticket.status == ParkingTicketStatus.paid) {
      // Pago confirmado — notificar al padre para cerrar WebView
      widget.onPaymentConfirmed?.call();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
                    if (controller.generatedCode != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Código de prueba: ${controller.generatedCode}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              color: colorScheme.onSecondaryContainer,
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: controller.generatedCode!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Código copiado al portapapeles')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    if (controller.generatedCode == null && !controller.isLoading && ticket == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => controller.generateTestCode(),
                            icon: const Icon(Icons.generating_tokens),
                            label: const Text('Generar código de prueba'),
                          ),
                        ),
                      ),
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
                      const SizedBox(height: 12),

                      // ── Banner de confirmación cuando el pago fue procesado ──
                      if (ticket.status == ParkingTicketStatus.paid) ...[
                        _PaymentSuccessBanner(
                          exitCode: ticket.exitCode,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Botones de pago (solo si está pendiente) ──
                      if (ticket.status == ParkingTicketStatus.pending) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: FilledButton(
                                onPressed: controller.isSubmitting
                                    ? null
                                    : () async {
                                        if (ticket.existingPaymentUrl != null &&
                                            widget.onOpenPaymentUrl != null) {
                                          widget.onOpenPaymentUrl!(ticket.existingPaymentUrl!);
                                          return;
                                        }
                                        
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
                                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                                    : Text(ticket.existingPaymentUrl != null ? 'Continuar pago' : 'Pagar'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton(
                                onPressed: controller.isSubmitting
                                    ? null
                                    : () async {
                                        final success = await controller.simulatePayment();
                                        if (!mounted) return;
                                        if (success) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Pago simulado con éxito.')),
                                          );
                                        }
                                      },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Simular', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                        ),
                      ],
                      
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isLoading,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
            ],
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: 'Ej: A1B2C3',
              floatingLabelBehavior: FloatingLabelBehavior.never,
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52, // Roughly matches the TextField height
          child: FilledButton(
            onPressed: isLoading ? null : onSearch,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isLoading 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)
                  )
                : const Icon(Icons.search),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalle del ticket',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
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

class _PaymentSuccessBanner extends StatelessWidget {
  final String? exitCode;

  const _PaymentSuccessBanner({this.exitCode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final successColor = colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: successColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: successColor.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: successColor,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            '¡Pago confirmado!',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: successColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tu ticket ha sido pagado exitosamente.\nYa puedes dirigirte a la salida del estacionamiento.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          if (exitCode != null && exitCode!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: successColor.withOpacity(0.3)),
              ),
              child: Text(
                'Código de salida: $exitCode',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
