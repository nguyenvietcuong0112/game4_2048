import 'package:flutter/material.dart';

/// Preview screen for the extracted Flower Merge flower stages, petals,
/// bloom burst frames, sunburst rays, and animated butterfly parts.
class FlowerAssetsTestScreen extends StatelessWidget {
  const FlowerAssetsTestScreen({super.key});

  static const _flowerTypes = [
    _FlowerEntry('Pink Tulip (Vase 1)', 'tulip', Colors.pink),
    _FlowerEntry('Trio Daisies (Vase 2)', 'daisy', Colors.purpleAccent),
    _FlowerEntry('Golden Sunflowers (Vase 3)', 'sunflower', Colors.amber),
    _FlowerEntry('Scarlet Poppies (Vase 4)', 'poppy', Colors.redAccent),
    _FlowerEntry('Crystal Lotus (Vase 5+)', 'lotus', Colors.pinkAccent),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      appBar: AppBar(
        title: const Text('🌸 Flower Stages & FX Preview'),
        backgroundColor: const Color(0xFF1D1454),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in _flowerTypes) ...[
            _sectionTitle('${f.name} — Stages 0 -> 3 + Petal'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int st = 0; st < 4; st++)
                    Container(
                      width: 112,
                      height: 112,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: f.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: f.color.withValues(alpha: 0.35)),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.asset(
                                'assets/images/flowers/${f.key}_stage_$st.webp',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            left: 6,
                            child: Text(
                              st == 0 ? 'Bud' : 'S$st',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    width: 64,
                    height: 112,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/flowers/petal_${f.key}.webp',
                          width: 28,
                          height: 36,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Petal',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          _sectionTitle('Bloom Burst Sequence (SX_effect_ywbd)'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (i) {
              return Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset('assets/images/flowers/fx_burst_$i.webp'),
              );
            }),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Sunburst Rays, Sparkles & Butterfly Parts'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _FxBox('Sunburst Rays', 'fx_bloom_rays.webp', 110),
              _FxBox('Sparkle', 'fx_sparkle.webp', 70),
              _FxBox('Glint', 'fx_glint.webp', 70),
              _FxBox('Wing L', 'fx_butterfly_wing_l.webp', 85),
              _FxBox('Body', 'fx_butterfly_body.webp', 65),
              _FxBox('Wing R', 'fx_butterfly_wing_r.webp', 85),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _FxBox extends StatelessWidget {
  final String label;
  final String fileName;
  final double size;
  const _FxBox(this.label, this.fileName, this.size);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.asset('assets/images/flowers/$fileName', fit: BoxFit.contain),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }
}

class _FlowerEntry {
  final String name;
  final String key;
  final Color color;
  const _FlowerEntry(this.name, this.key, this.color);
}
