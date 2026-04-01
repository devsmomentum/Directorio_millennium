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

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

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
  final int _timeoutSeconds = 45; // Tiempo máximo sin tocar la pantalla
  bool _isConfiguring = false; // Evita que el técnico sea expulsado

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
    _secretTapTimer?.cancel();
    super.dispose();
  }

  // 🚀 LÓGICA DEL TIMEOUT FANTASMA
  void _startInactivityTimer() {
    if (_isConfiguring)
      return; // Si el técnico está configurando, no hacemos nada

    _inactivityTimer?.cancel(); // Matamos el reloj anterior
    _inactivityTimer = Timer(
      Duration(seconds: _timeoutSeconds),
      _handleInactivity,
    );
  }

  void _handleInactivity() {
    // 1. Doble check de seguridad sobre el estado del Widget
    if (!mounted || _isConfiguring) return;

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

    final TextEditingController passController = TextEditingController();
    bool isError = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: Colors.pinkAccent),
                  SizedBox(width: 10),
                  Text(
                    'MDM SETUP',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ingrese la contraseña de aprovisionamiento:',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Contraseña',
                      hintStyle: const TextStyle(color: Colors.white30),
                      errorText: isError ? 'Acceso denegado' : null,
                      filled: true,
                      fillColor: Colors.black,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.pinkAccent),
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
                  child: const Text(
                    'CANCELAR',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
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
                  child: const Text(
                    'ENTRAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
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

  @override
  Widget build(BuildContext context) {
    // 🚀 ENVOLVEMOS TODO EN UN LISTENER
    return Listener(
      behavior: HitTestBehavior
          .translucent, // Captura toques en cualquier lugar de la pantalla
      onPointerDown: (_) => _startInactivityTimer(), // Dedo toca
      onPointerMove: (_) => _startInactivityTimer(), // Dedo arrastra
      onPointerUp: (_) => _startInactivityTimer(), // Dedo suelta
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: _screens[_currentIndex],
        bottomNavigationBar: Container(
          height: 75,
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            border: Border(top: BorderSide(color: Colors.white10)),
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
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.pinkAccent : Colors.white54,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.pinkAccent : Colors.white54,
                fontSize: 12,
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
  const KioskSetupModal({Key? key, required this.onClose}) : super(key: key);

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
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      alert('Error: $e');
    }
  }

  void alert(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Vincular Hardware',
        style: TextStyle(color: Colors.white),
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(
                child: CircularProgressIndicator(color: Colors.pinkAccent),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID Físico detectado: $_hardwareId',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Seleccione el perfil a asignar:',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),

                if (_availableKiosks.isEmpty)
                  const Text(
                    '❌ No hay perfiles de kioscos disponibles en el panel Admin.',
                    style: TextStyle(color: Colors.redAccent),
                  )
                else
                  DropdownButtonFormField<String>(
                    dropdownColor: Colors.black,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    value: _selectedKioskId,
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
          child: const Text(
            'CANCELAR',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        if (_availableKiosks.isNotEmpty)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: _isLoading || _selectedKioskId == null
                ? null
                : _linkDevice,
            child: const Text(
              'VINCULAR EQUIPO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
