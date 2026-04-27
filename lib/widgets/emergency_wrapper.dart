import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:media_kit/media_kit.dart';
import '../theme/app_theme.dart';

class EmergencyWrapper extends StatefulWidget {
  final Widget child;
  const EmergencyWrapper({super.key, required this.child});

  @override
  State<EmergencyWrapper> createState() => _EmergencyWrapperState();
}

class _EmergencyWrapperState extends State<EmergencyWrapper> with SingleTickerProviderStateMixin {
  bool _isEmergencyActive = false;
  String _emergencyFloor = 'Desconocido';
  String _emergencyLocation = 'Ubicación desconocida';
  String _myKioskId = '';
  bool _isOrigin = false;
  
  RealtimeChannel? _channel;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Linux usa media_kit (ya inicializado en main.dart).
  // Android y resto usan audioplayers.
  AudioPlayer? _audioPlayer;
  Player? _mkPlayer;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.0, end: 15.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initEmergencyListener();
  }

  Future<void> _initEmergencyListener() async {
    final response = await Supabase.instance.client
        .from('kiosks')
        .select('*')
        .eq('is_emergency_active', true)
        .limit(1);

    if (response.isNotEmpty) {
      await _updateEmergencyState(response.first);
    }

    _channel = Supabase.instance.client
        .channel('public:kiosks:emergency')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kiosks',
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord != null && newRecord['is_emergency_active'] == true) {
              await _updateEmergencyState(newRecord);
            } else {
              await _checkIfAnyEmergency();
            }
          },
        )
        .subscribe();
  }

  Future<void> _checkIfAnyEmergency() async {
    final response = await Supabase.instance.client
        .from('kiosks')
        .select('*')
        .eq('is_emergency_active', true)
        .limit(1);

    if (response.isNotEmpty) {
      await _updateEmergencyState(response.first);
    } else {
      await _stopAlarm();
      if (mounted) {
        setState(() {
          _isEmergencyActive = false;
          _isOrigin = false;
        });
      }
    }
  }

  Future<void> _updateEmergencyState(Map<String, dynamic> kioskData) async {
    final prefs = await SharedPreferences.getInstance();
    final currentKioskId = prefs.getString('kiosk_id') ?? '';
    final isOrigin = kioskData['id'].toString() == currentKioskId;

    if (mounted) {
      setState(() {
        _isEmergencyActive = true;
        _emergencyFloor = kioskData['floor_level']?.toString() ?? 'Desconocido';

        final name = kioskData['name']?.toString() ?? '';
        final loc = kioskData['location']?.toString() ?? '';
        final locName = kioskData['location_name']?.toString() ?? '';

        String finalLocation = '';
        if (loc.isNotEmpty) {
          finalLocation = loc;
        } else if (locName.isNotEmpty) {
          finalLocation = locName;
        } else {
          finalLocation = name.isNotEmpty ? name : 'Ubicación desconocida';
        }

        _emergencyLocation = finalLocation;
        _myKioskId = currentKioskId;
        _isOrigin = isOrigin;
      });
    }

    if (isOrigin) {
      await _playAlarm();
    }
  }

  Future<void> _playAlarm() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      _mkPlayer ??= Player();
      await _mkPlayer!.open(Media('asset:///assets/audio/alarma.mp3'));
      _mkPlayer!.setPlaylistMode(PlaylistMode.loop);
    } else {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer!.play(AssetSource('audio/alarma.mp3'));
    }
  }

  Future<void> _stopAlarm() async {
    await _audioPlayer?.stop();
    await _mkPlayer?.stop();
  }

  Future<void> _deactivateEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final currentKioskId = prefs.getString('kiosk_id') ?? '';
    
    if (currentKioskId.isNotEmpty) {
      await Supabase.instance.client
          .from('kiosks')
          .update({'is_emergency_active': false})
          .eq('id', currentKioskId);
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _pulseController.dispose();
    _audioPlayer?.dispose();
    _mkPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isEmergencyActive)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Color(0xFF220000), 
                      Color(0xFF000000), 
                    ],
                  ),
                ),
                child: SafeArea(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      width: 600,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFC0392B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'ALERTA ACTIVA',
                                    style: TextStyle(
                                      color: Color(0xFFC0392B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.0,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'MILLENNIUM MALL',
                                style: TextStyle(
                                  color: Color(0xFFC0392B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 60),

                          // ── Escudo Central Actualizado ──
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withOpacity(0.4),
                                        blurRadius: 20 + _pulseAnimation.value * 1.5,
                                        spreadRadius: 3 + (_pulseAnimation.value / 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.security,
                                    color: Colors.redAccent,
                                    size: 110,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 60),

                          // ── Título ──
                          const Text(
                            'EMERGENCIA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              letterSpacing: 4.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'PROTOCOLO DE SEGURIDAD ACTIVADO',
                            style: TextStyle(
                              color: Color(0xFFC0392B),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              fontFamily: 'Courier',
                            ),
                          ),
                          const SizedBox(height: 60),

                          // ── Panel de datos ──
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.background, 
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _buildDataRow(
                                  icon: Icons.layers_rounded,
                                  title: 'PISO DE LA EMERGENCIA',
                                  value: _emergencyFloor,
                                ),
                                const Divider(color: Colors.white10),
                                _buildDataRow(
                                  icon: Icons.location_on_rounded,
                                  title: 'UBICACIÓN',
                                  value: _emergencyLocation,
                                ),
                                const Divider(color: Colors.white10),
                                _buildDataRow(
                                  icon: Icons.access_time_rounded,
                                  title: 'HORA',
                                  customWidget: const _LiveClockText(), // <-- Se usa el widget aislado
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 60),

                          // ── Lógica Dinámica: Botón o Mensaje de Estado ──
                          if (_isOrigin) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                                  backgroundColor: AppColors.background,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _deactivateEmergency,
                                icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                                label: const Text(
                                  'DESACTIVAR',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_user_rounded,
                                    color: Color(0xFF7A4A3E),
                                    size: 18,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Seguridad ha sido notificada',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDataRow({
    required IconData icon,
    required String title,
    String? value,
    Widget? customWidget, // <-- Añadido soporte para widgets personalizados
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF7A4A3E),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF7A4A3E),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                customWidget ?? // <-- Renderiza el customWidget o el texto por defecto
                Text(
                  value ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget independiente para el reloj en vivo ──
class _LiveClockText extends StatefulWidget {
  const _LiveClockText();

  @override
  State<_LiveClockText> createState() => _LiveClockTextState();
}

class _LiveClockTextState extends State<_LiveClockText> {
  late Timer _timer;
  String _timeString = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (mounted) {
      final now = DateTime.now();
      setState(() {
        _timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeString,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}