import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'kiosk_selector.dart';
import 'emergency_button.dart';

/// Header global persistente para todas las pantallas del kiosco.
///
/// Se coloca dentro del body del [Scaffold] principal, debajo del banner
/// publicitario superior. Diseñado para ser la única cabecera de la app,
/// reemplazando cualquier logo o header quemado en pantallas individuales.
class AppHeader extends StatefulWidget {
  /// Texto que aparece debajo de "MILLENNIUM MALL".
  /// Cambia dinámicamente según la vista activa.
  final String subtitle;

  const AppHeader({
    super.key,
    this.subtitle = 'DIRECTORIO INTERACTIVO',
  });

  /// Altura del contenido principal del header (sin las líneas de gradiente).
  static const double _headerHeight = 72.0;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  late Timer _clockTimer;
  String _timeString = '';
  String _dateString = '';

  // Nombres en español para evitar dependencia extra de intl.
  static const List<String> _weekDays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  static const List<String> _months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _updateClock();
    // Actualizar el reloj cada segundo.
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final period = now.hour >= 12 ? 'p. m.' : 'a. m.';
    final minute = now.minute.toString().padLeft(2, '0');

    final dayName = _weekDays[now.weekday - 1];
    final monthName = _months[now.month - 1];

    if (mounted) {
      setState(() {
        _timeString = '${hour.toString().padLeft(2, '0')}:$minute $period';
        _dateString = '$dayName, ${now.day} de $monthName';
      });
    }
  }

 @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface, // Fondo principal del header
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Para que la columna no ocupe toda la pantalla
          children: [
            // ── LÍNEA SUPERIOR CON GRADIENTE ──
            Container(
              height: 2.0, // Grosor del borde
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
              ),
            ),

            // ── CONTENIDO PRINCIPAL DEL HEADER ──
            SizedBox(
              height: AppHeader._headerHeight - 4.0, // Descontamos los 4px de ambas líneas
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 420;
                  final emergencySize = isCompact ? 38.0 : 44.0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        // ── CENTRO: Logo + Título + Reloj ──
                        Expanded(
                          child: Row(
                            children: [
                              // Logo desde Supabase Storage.
                              // Zona oculta de long-press: 3 segundos sobre el
                              // logo abren el selector de kiosco (útil para
                              // depurar en una laptop como si fuera un kiosco).
                              KioskLongPressZone(
                                child: Container(
                                  // Área ampliada para capturar el long-press sin
                                  // alterar el layout visible del logo.
                                  width: 56,
                                  height: 56,
                                  alignment: Alignment.center,
                                  color: AppColors.transparent,
                                  child: Image.network(
                                    'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/logo.png',
                                    height: 40,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.apartment_rounded,
                                      color: AppColors.textPrimary,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Nombre del mall + subtítulo
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MILLENNIUM MALL',
                                      style: AppTextStyles.buttonText.copyWith(
                                        fontSize: 16,
                                        letterSpacing: 1.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    ShaderMask(
                                      shaderCallback: (bounds) =>
                                          AppColors.primaryGradient
                                              .createShader(bounds),
                                      child: Text(
                                        widget.subtitle,
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          letterSpacing: 1.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Reloj y fecha (alineados a la derecha del centro)
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _timeString,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.body.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: isCompact ? 12 : 14,
                                      ),
                                    ),
                                    if (!isCompact)
                                      Text(
                                        _dateString,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondaryMuted,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Botón de emergencia
                              EmergencyButton(size: emergencySize),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── LÍNEA INFERIOR CON GRADIENTE ──
            Container(
              height: 2.0, // Grosor del borde
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
