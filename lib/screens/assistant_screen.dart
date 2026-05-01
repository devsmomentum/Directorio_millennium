import 'package:flutter/material.dart';

import '../widgets/screen_ad_banners.dart';

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: ScreenAdBanners(
        showTop: false,
        showBottom: false,
        child: Stack(
          children: [
            // Botón cerrar
            Positioned(
              top: 50,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Si el ancho es mayor a 700, asumimos que es modo Kiosko o Tablet
                  bool isWide = constraints.maxWidth > 700;

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 60.0 : 25.0,
                      vertical: 40.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- HEADER ANIMADO ---
                        _EntranceAnimation(
                          delay: 0,
                          child: _buildHeader(isWide),
                        ),

                        const SizedBox(height: 40),

                        // --- CUERPO RESPONSIVE ---
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: _EntranceAnimation(
                                  delay: 200,
                                  child: _buildQRSection(isWide),
                                ),
                              ),
                              const SizedBox(width: 60),
                              Expanded(
                                flex: 6,
                                child: _EntranceAnimation(
                                  delay: 400,
                                  child: _buildActionsList(isWide),
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _EntranceAnimation(
                                delay: 200,
                                child: _buildQRSection(isWide),
                              ),
                              const SizedBox(height: 40),
                              _EntranceAnimation(
                                delay: 400,
                                child: _buildActionsList(isWide),
                              ),
                            ],
                          ),

                        const SizedBox(height: 50),
                        _buildFooter(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- COMPONENTES ---

  Widget _buildHeader(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Text(
                '⚡ SUPERAPI · CONSERJE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Lleva el directorio\nen tu bolsillo',
          style: TextStyle(
            color: Colors.white,
            fontSize: isWide ? 56 : 38,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildQRSection(bool isWide) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Colors.greenAccent, Colors.pinkAccent],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Image.network(
              'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=MillenniumMall',
              width: isWide ? 300 : 250,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Escanea con tu cámara',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildActionsList(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActionItem(Icons.map, 'Mapa interactivo de tiendas'),
        _buildActionItem(Icons.movie, 'Cartelera de cine actualizada'),
        _buildActionItem(Icons.local_parking, 'Pago de ticket online'),
        _buildActionItem(Icons.celebration, 'Eventos del Millennium Mall'),
      ],
    );
  }

  Widget _buildActionItem(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 24),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const Center(
      child: Text(
        '© 2026 Millennium Mall - Caracas',
        style: TextStyle(color: Colors.white24, fontSize: 12),
      ),
    );
  }
}

// --- CLASE PARA LA ANIMACIÓN ---
class _EntranceAnimation extends StatelessWidget {
  final Widget child;
  final int delay;

  const _EntranceAnimation({required this.child, required this.delay});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
