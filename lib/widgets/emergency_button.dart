import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyButton extends StatelessWidget {
  final double size;
  
  const EmergencyButton({
    super.key,
    this.size = 50.0,
  });

  Future<void> _triggerEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final myKioskId = prefs.getString('kiosk_id');
    if (myKioskId == null || myKioskId.isEmpty) return;

    await Supabase.instance.client
        .from('kiosks')
        .update({'is_emergency_active': true})
        .eq('id', myKioskId);

    try {
      await Supabase.instance.client.functions.invoke(
        'send-emergency-whatsapp',
        body: {'kiosk_id': myKioskId},
      );
    } catch (e) {
      // El fallo en WhatsApp no debe bloquear la alerta local ya activada.
      debugPrint('[EmergencyButton] Error al enviar WhatsApp: $e');
    }
  }

  void _showConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  Color(0xFF220000),
                  Color(0xFF000000),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(30),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.report_problem_outlined,
                    color: Colors.redAccent,
                    size: 70,
                  ),
                ),
                const SizedBox(height: 25),
                const Text(
                  'CONFIRMAR ACTIVACIÓN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '¿Está seguro de que desea activar el protocolo de emergencia en este kiosco?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF330000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'AVISO DE PENALIZACIÓN',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Advertencia: El uso indebido o la emisión de falsas alarmas será severamente penalizado según el reglamento de seguridad de la administración.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B0000), // Actualizado a rojo oscuro
                        foregroundColor: Colors.white,
                        elevation: 5,
                        shadowColor: Colors.red.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                      ),
                      onPressed: () {
                        Navigator.of(dialogContext).pop(); 
                        _triggerEmergency(); 
                      },
                      child: const Text(
                        'PROCEDER CON LA ALERTA',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                    ),
                  ],
                ),
              ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showConfirmationDialog(context),
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Degradado mucho más profundo y serio
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8B0000), // Rojo sangre oscuro
              Color(0xFF3E0000), // Rojo casi negro, empata con el fondo de la vista
            ],
          ),
          // Borde sutil rojo accent para que no desentone
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.4),
            width: 2,
          ),
          // Sombra más densa y pesada
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B0000).withOpacity(0.7),
              blurRadius: 25,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.sos_rounded,
            color: Colors.white,
            size: 32, 
          ),
        ),
      ),
    );
  }
}