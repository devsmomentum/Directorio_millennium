import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/kiosk_bus.dart';
import '../theme/app_theme.dart';

// MapScreen maneja los pisos como strings (ej. 'RG', 'C1', etc.)

// ═════════════════════════════════════════════════════════════════════════════
// Zona invisible de long-press: envuelve un child y, tras mantener presionado
// [holdDuration] segundos, abre el selector de kiosco. Durante la presión se
// pinta un anillo sutil de progreso sobre el child para dar feedback al
// técnico (sin delatar la zona a usuarios normales).
// ═════════════════════════════════════════════════════════════════════════════
class KioskLongPressZone extends StatefulWidget {
  final Widget child;
  final Duration holdDuration;

  /// Callback opcional cuando el técnico confirma un kiosco nuevo.
  final VoidCallback? onKioskSelected;

  const KioskLongPressZone({
    super.key,
    required this.child,
    this.holdDuration = const Duration(seconds: 3),
    this.onKioskSelected,
  });

  @override
  State<KioskLongPressZone> createState() => _KioskLongPressZoneState();
}

class _KioskLongPressZoneState extends State<KioskLongPressZone> {
  Timer? _progressTimer;
  Timer? _completionTimer;
  double _progress = 0.0;
  bool _isPressed = false;

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _progressTimer?.cancel();
    _completionTimer?.cancel();
    _progressTimer = null;
    _completionTimer = null;
  }

  void _startPress() {
    final totalMs = widget.holdDuration.inMilliseconds;
    const tickMs = 50;
    _isPressed = true;
    _progress = 0.0;

    _progressTimer = Timer.periodic(
      const Duration(milliseconds: tickMs),
      (_) {
        if (!mounted) return;
        setState(() {
          _progress = (_progress + tickMs / totalMs).clamp(0.0, 1.0);
        });
      },
    );

    _completionTimer = Timer(widget.holdDuration, () {
      _cancelTimers();
      if (!mounted) return;
      setState(() {
        _isPressed = false;
        _progress = 0.0;
      });
      _openSelector();
    });
  }

  void _cancelPress() {
    _cancelTimers();
    if (!mounted) return;
    setState(() {
      _isPressed = false;
      _progress = 0.0;
    });
  }

  Future<void> _openSelector() async {
    final selected = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const KioskSelectorDialog(),
    );
    if (selected == true) {
      widget.onKioskSelected?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startPress(),
      onLongPressEnd: (_) => _cancelPress(),
      onLongPressCancel: _cancelPress,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_isPressed)
            Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 2.5,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                    backgroundColor: AppColors.primary.withAlpha(40),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Diálogo: lista kioscos de la BD con nombre, ubicación y piso.
// - `kiosks.floor` (text) tiene prioridad si está poblado.
// - Fallback: join `kiosks.node_id → map_nodes.floor_level` (string).
// Al confirmar guarda en SharedPreferences y dispara `KioskBus.notifyKioskChanged()`.
// ═════════════════════════════════════════════════════════════════════════════
class KioskSelectorDialog extends StatefulWidget {
  const KioskSelectorDialog({super.key});

  @override
  State<KioskSelectorDialog> createState() => _KioskSelectorDialogState();
}

class _KioskSelectorDialogState extends State<KioskSelectorDialog> {
  bool _isLoading = true;
  String? _errorMessage;

  List<_KioskRow> _kiosks = [];
  String? _selectedKioskId;
  String? _currentKioskId;

  @override
  void initState() {
    super.initState();
    _loadKiosks();
  }

  Future<void> _loadKiosks() async {
    try {
      final client = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      _currentKioskId = prefs.getString('kiosk_id');

      // Traemos kioscos y nodos en paralelo. Los nodos nos dan el piso
      // numérico de cada kiosco vía node_id.
      final responses = await Future.wait([
        client.from('kiosks').select().order('name'),
        client.from('map_nodes').select('id, floor_level'),
      ]);

      final kiosksRaw = List<Map<String, dynamic>>.from(responses[0] as List);
      final nodesRaw = List<Map<String, dynamic>>.from(responses[1] as List);

      final nodeFloorById = <String, String>{
        for (final n in nodesRaw)
          (n['id'] as String): n['floor_level'].toString(),
      };

      final rows = kiosksRaw.map((k) {
        final floorText = (k['floor'] as String?)?.trim();
        final nodeId = k['node_id'] as String?;
        final floorFromNode = nodeId != null ? nodeFloorById[nodeId] : null;

        String? floorLabel;
        if (floorText != null && floorText.isNotEmpty) {
          floorLabel = floorText.toUpperCase();
        } else if (floorFromNode != null) {
          floorLabel = floorFromNode;
        }

        return _KioskRow(
          id: k['id'] as String,
          name: (k['name'] as String?) ?? 'Sin nombre',
          location: k['location'] as String?,
          locationName: k['location_name'] as String?,
          status: k['status'] as String?,
          floorLabel: floorLabel,
          nodeId: nodeId,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _kiosks = rows;
        _selectedKioskId = _currentKioskId;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[KioskSelector] Error cargando kioscos: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudieron cargar los kioscos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final id = _selectedKioskId;
    if (id == null) return;

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kiosk_id', id);

      // Notificar a toda la app (MapScreen y otras pantallas dependientes).
      KioskBus.notifyKioskChanged();

      if (!mounted) return;
      Navigator.of(context).pop(true);
      final name = _kiosks.firstWhere((k) => k.id == id).name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kiosco actualizado → $name'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceLight,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tv_rounded, color: AppColors.primary, size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'SELECCIONAR KIOSCO',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondaryMuted),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Simula que este dispositivo es uno de los kioscos físicos. '
              'Determina node_id, piso y rutas del mapa.',
              style: TextStyle(
                color: AppColors.textSecondaryMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const SizedBox(
                height: 140,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              )
            else if (_kiosks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No hay kioscos registrados en la base de datos.',
                  style: TextStyle(color: AppColors.error, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _kiosks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildKioskTile(_kiosks[i]),
                ),
              ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withAlpha(80),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (_isLoading || _selectedKioskId == null)
                    ? null
                    : _confirm,
                child: const Text(
                  'CONFIRMAR KIOSCO',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKioskTile(_KioskRow kiosk) {
    final isSelected = _selectedKioskId == kiosk.id;
    final isCurrent = _currentKioskId == kiosk.id;
    final missingNode = kiosk.nodeId == null;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedKioskId = kiosk.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withAlpha(38)
              : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppColors.primary : AppColors.textHint,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          kiosk.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withAlpha(51),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ACTUAL',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (kiosk.floorLabel != null)
                        _chip(
                          icon: Icons.layers_rounded,
                          label: 'Piso ${kiosk.floorLabel}',
                          tint: AppColors.primary,
                        )
                      else
                        _chip(
                          icon: Icons.warning_amber_rounded,
                          label: 'Sin piso',
                          tint: AppColors.warning,
                        ),
                      if (kiosk.locationName != null &&
                          kiosk.locationName!.isNotEmpty)
                        _chip(
                          icon: Icons.place_outlined,
                          label: kiosk.locationName!,
                          tint: AppColors.textSecondaryMuted,
                        ),
                      if (missingNode)
                        _chip(
                          icon: Icons.link_off_rounded,
                          label: 'Sin nodo',
                          tint: AppColors.error,
                        ),
                      if (kiosk.status != null && kiosk.status != 'active')
                        _chip(
                          icon: Icons.info_outline_rounded,
                          label: kiosk.status!,
                          tint: AppColors.textSecondaryMuted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: tint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KioskRow {
  final String id;
  final String name;
  final String? location;
  final String? locationName;
  final String? status;
  final String? floorLabel;
  final String? nodeId;

  const _KioskRow({
    required this.id,
    required this.name,
    required this.location,
    required this.locationName,
    required this.status,
    required this.floorLabel,
    required this.nodeId,
  });
}
