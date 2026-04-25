import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'services_screen.dart';
import 'map_screen.dart';
import 'assistant_screen.dart';
import 'coupons_screen.dart'; // 🚀 NUEVO IMPORT
import '../widgets/screen_ad_banners.dart';
import '../widgets/app_header.dart';
import '../widgets/inactivity_warning.dart';
import '../widgets/map_view_web.dart' show MapInteractionNotification;
import '../theme/app_theme.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 1; // Empezamos en Directorio

  // --- VARIABLES PARA EL EASTER EGG ---
  int _secretTapCount = 0;
  Timer? _secretTapTimer;

  // 🚀 VARIABLES PARA EL TIMEOUT DE INACTIVIDAD
  Timer? _inactivityTimer;
  Timer? _warningTimer;
  final int _timeoutSeconds = 60; // Tiempo máximo sin tocar la pantalla
  final int _warningBeforeSeconds = 10; // Aviso 10 segundos antes
  bool _isConfiguring = false; // Evita que el técnico sea expulsado
  bool _showWarning = false; // Controla la visibilidad del overlay de aviso

  // 1. Aquí se definen las pantallas reales
  final List<Widget> _screens = [
    const SizedBox(), // Se usa para volver al Home
    const MapScreen(),
    const ServicesScreen(),
    const AssistantScreen(),
    const CouponsScreen(), // 🚀 4. NUEVA PANTALLA DE CUPONES
  ];

  @override
  void initState() {
    super.initState();
    _startInactivityTimer(); // 🚀 Arrancamos el reloj al entrar
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel(); // 🚀 Limpiamos el reloj al salir
    _warningTimer?.cancel();
    _secretTapTimer?.cancel();
    super.dispose();
  }

  // 🚀 LÓGICA DEL TIMEOUT FANTASMA (con aviso previo)
  void _startInactivityTimer() {
    if (_isConfiguring) {
      return; // Si el técnico está configurando, no hacemos nada
    }

    // Cancelar timers anteriores
    _inactivityTimer?.cancel();
    _warningTimer?.cancel();

    // Ocultar el warning si estaba visible
    if (_showWarning && mounted) {
      setState(() => _showWarning = false);
    }

    // Timer 1: Mostrar aviso a los (timeout - 10) segundos
    final warningDelay = _timeoutSeconds - _warningBeforeSeconds;
    _warningTimer = Timer(
      Duration(seconds: warningDelay),
      () {
        if (!mounted || _isConfiguring) return;
        setState(() => _showWarning = true);
      },
    );

    // Timer 2: Ejecutar timeout completo a los 45 segundos
    _inactivityTimer = Timer(
      Duration(seconds: _timeoutSeconds),
      _handleInactivity,
    );
  }

  /// Reinicia el conteo completo y oculta el aviso.
  void _dismissWarning() {
    _startInactivityTimer();
  }

  void _handleInactivity() {
    // 1. Doble check de seguridad sobre el estado del Widget
    if (!mounted || _isConfiguring) return;

    // Ocultar el warning
    setState(() => _showWarning = false);

    // 🚀 2. Verificamos que el árbol de navegación esté intacto y permita regresar
    if (Navigator.of(context).canPop()) {
      debugPrint("⏳ TIMEOUT ALCANZADO: Volviendo a la publicidad...");
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _onItemTapped(int index) {
    // 🚀 LÓGICA DEL EASTER EGG (Botón 3 = Asistente)
    if (index == 3) {
      _secretTapCount++;
      _secretTapTimer?.cancel();
      // Si el técnico deja de tocar por 1 segundo, se reinicia el contador
      _secretTapTimer = Timer(const Duration(seconds: 1), () {
        _secretTapCount = 0;
      });

      // ¡BINGO! 5 Toques rápidos
      if (_secretTapCount >= 5) {
        _secretTapCount = 0;
        _showAdminPasswordDialog();
      }
    }

    // Comportamiento normal de la navegación
    if (index == 0) {
      Navigator.pop(context); // Volver a la pantalla de videos
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  // --- MODAL 1: CONTRASEÑA DE SEGURIDAD ---
  void _showAdminPasswordDialog() {
    _isConfiguring = true; // 🚀 Pausamos el timeout
    _inactivityTimer?.cancel();
    _warningTimer?.cancel();
    if (mounted) setState(() => _showWarning = false);

    final TextEditingController passController = TextEditingController();
    bool isError = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surfaceLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text('MDM SETUP', style: AppTextStyles.dialogTitle),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ingrese la contraseña de aprovisionamiento:',
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Contraseña',
                      hintStyle: AppTextStyles.body.copyWith(
                        color: AppColors.textHint,
                      ),
                      errorText: isError ? 'Acceso denegado' : null,
                      filled: true,
                      fillColor: AppColors.background,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _isConfiguring = false; // 🚀 Reactivamos el timeout
                    _startInactivityTimer();
                    Navigator.pop(context);
                  },
                  child: Text(
                    'CANCELAR',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondaryMuted,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () {
                    // 🚀 CLAVE HARDCODEADA
                    if (passController.text == 'morna2026') {
                      Navigator.pop(context);
                      _showKioskSetupDialog();
                    } else {
                      setDialogState(() => isError = true);
                    }
                  },
                  child: Text(
                    'ENTRAR',
                    style: AppTextStyles.buttonText.copyWith(letterSpacing: 0),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- MODAL 2: VINCULACIÓN DE HARDWARE ---
  void _showKioskSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => KioskSetupModal(
        onClose: () {
          _isConfiguring = false; // 🚀 Reactivamos el timeout al terminar
          _startInactivityTimer();
        },
      ),
    );
  }

  /// Devuelve el subtítulo del header según la pestaña activa.
  String get _headerSubtitle {
    switch (_currentIndex) {
      case 0:
        return 'INICIO';
      case 1:
        return 'DIRECTORIO INTERACTIVO';
      case 2:
        return 'SERVICIOS';
      case 3:
        return 'ASISTENTE VIRTUAL';
      case 4:
        return 'CUPONES Y OFERTAS';
      default:
        return 'DIRECTORIO INTERACTIVO';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 ENVOLVEMOS TODO EN UN LISTENER
    return Listener(
      behavior: HitTestBehavior
          .translucent, // Captura toques en cualquier lugar de la pantalla
      onPointerDown: (_) => _startInactivityTimer(), // Dedo toca
      onPointerMove: (_) => _startInactivityTimer(), // Dedo arrastra
      onPointerUp: (_) => _startInactivityTimer(), // Dedo suelta
      child: NotificationListener<MapInteractionNotification>(
        onNotification: (_) {
          _startInactivityTimer();
          return true; // Detenemos la propagación
        },
        child: Stack(
          children: [
          // ── Scaffold completo (body + bottomNav) ──
          Scaffold(
            backgroundColor: AppColors.background,
            body: Column(
              children: [
                // Banner publicitario superior (10% fijo, igual que el inferior)
                const TopNavigationAdBanner(),
                // Header unificado (debajo del banner)
                AppHeader(subtitle: _headerSubtitle),
                // Contenido de las pestañas
                Expanded(
                  child: IndexedStack(index: _currentIndex, children: _screens),
                ),
              ],
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.divider)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavItem(Icons.home_outlined, 'Inicio', 0),
                      _buildNavItem(Icons.map_outlined, 'Directorio', 1),
                      // 🚀 NUEVO BOTÓN DE CUPONES
                      _buildNavItem(Icons.local_activity_outlined, 'Cupones', 4),
                      _buildNavItem(Icons.credit_card_outlined, 'Servicios', 2),
                      _buildNavItem(Icons.chat_bubble_outline, 'Asistente', 3),
                    ],
                  ),
                ),
                const BottomNavigationAdBanner(),
              ],
            ),
          ),

          // ── Overlay de inactividad — ENCIMA de todo el Scaffold ──
          if (_showWarning)
            Positioned.fill(
              child: InactivityWarning(
                countdownSeconds: _warningBeforeSeconds,
                onDismiss: _dismissWarning,
                onTimeout: _handleInactivity,
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: Container(
        color: AppColors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive
                  ? AppColors.primary
                  : AppColors.textSecondaryMuted,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.navLabel.copyWith(
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondaryMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 🚀 WIDGET SEPARADO PARA LA LÓGICA DE EMPAREJAMIENTO (MDM)
// ============================================================================
class KioskSetupModal extends StatefulWidget {
  final VoidCallback onClose; // 🚀 Para avisar que ya cerramos
  const KioskSetupModal({super.key, required this.onClose});

  @override
  State<KioskSetupModal> createState() => _KioskSetupModalState();
}

class _KioskSetupModalState extends State<KioskSetupModal> {
  bool _isLoading = true;
  String _hardwareId = '';
  List<Map<String, dynamic>> _availableKiosks = [];
  String? _selectedKioskId;

  @override
  void initState() {
    super.initState();
    _initSetup();
  }

  Future<void> _initSetup() async {
    // 1. Obtener ID del Hardware
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _hardwareId = androidInfo.id; // 🚀 El ID único de la placa Sunmi
    } else {
      _hardwareId = 'hardware_test_id_${DateTime.now().millisecondsSinceEpoch}';
    }

    // 2. Buscar Kioscos "Libres" en Supabase
    final response = await Supabase.instance.client
        .from('kiosks')
        .select('*')
        .isFilter(
          'hardware_id',
          null,
        ); // Solo trae los que están esperando hardware

    if (mounted) {
      setState(() {
        _availableKiosks = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    }
  }

  Future<void> _linkDevice() async {
    if (_selectedKioskId == null) return;
    setState(() => _isLoading = true);

    try {
      // 1. Actualizar Supabase (Reclamar el perfil)
      await Supabase.instance.client
          .from('kiosks')
          .update({'hardware_id': _hardwareId, 'status': 'online'})
          .eq('id', _selectedKioskId!);

      // 2. Guardar en la memoria interna (Caché) para que Telemetría lo use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kiosk_id', _selectedKioskId!);
      await prefs.setString('hardware_id', _hardwareId);

      if (mounted) {
        widget.onClose(); // Avisamos que terminamos para reactivar Timeout
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Equipo vinculado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      alert('Error: $e');
    }
  }

  void alert(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Vincular Hardware', style: AppTextStyles.dialogTitle),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID Físico detectado: $_hardwareId',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondaryMuted,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Seleccione el perfil a asignar:',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),

                if (_availableKiosks.isEmpty)
                  Text(
                    '❌ No hay perfiles de kioscos disponibles en el panel Admin.',
                    style: AppTextStyles.body.copyWith(color: AppColors.error),
                  )
                else
                  DropdownButtonFormField<String>(
                    dropdownColor: AppColors.background,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.background,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    initialValue: _selectedKioskId,
                    items: _availableKiosks.map((kiosk) {
                      return DropdownMenuItem<String>(
                        value: kiosk['id'].toString(),
                        child: Text('${kiosk['name']} - ${kiosk['location']}'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedKioskId = val),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onClose(); // 🚀 Avisamos que cerramos para reactivar timeout
            Navigator.pop(context);
          },
          child: Text(
            'CANCELAR',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondaryMuted,
            ),
          ),
        ),
        if (_availableKiosks.isNotEmpty)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: _isLoading || _selectedKioskId == null
                ? null
                : _linkDevice,
            child: Text(
              'VINCULAR EQUIPO',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
