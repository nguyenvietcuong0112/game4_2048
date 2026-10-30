import 'package:flutter/material.dart';
import '../models/level_models.dart';
import 'unity_ui_kit.dart';

/// Native Unity-styled Level Selector Popup (`Background_Popup.png` + `Panel_Popup.png` +
/// `Button_Close.png` + 9-slice `Button_CTA.png` / `Button_Blue.png` tiles) allowing instant
/// jump across all 121 Campaign levels and 25 Bonus levels.
class LevelPickerSheet extends StatefulWidget {
  final LevelRepository repository;
  final int activeLevelNumber;
  final bool activeIsBonus;
  final int highestUnlockedLevel;
  final ValueChanged<LevelDefinition> onSelectLevel;

  const LevelPickerSheet({
    super.key,
    required this.repository,
    required this.activeLevelNumber,
    required this.activeIsBonus,
    required this.highestUnlockedLevel,
    required this.onSelectLevel,
  });

  @override
  State<LevelPickerSheet> createState() => _LevelPickerSheetState();
}

class _LevelPickerSheetState extends State<LevelPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.activeIsBonus ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final campaign = widget.repository.campaignLevels;
    final bonus = widget.repository.bonusLevels;
    final sheetH = MediaQuery.sizeOf(context).height * 0.80;

    return SizedBox(
      height: sheetH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: ux(context, 36),
            child: UnityNineSlice(
              sprite: 'Background_Popup.png',
              padding: EdgeInsets.fromLTRB(
                ux(context, 34),
                ux(context, 34),
                ux(context, 34),
                ux(context, 40),
              ),
              child: Column(
                children: [
                  SizedBox(height: ux(context, 8)),
                  const UnitySdfText(
                    'Select Level',
                    unityFontSize: 78,
                    material: UnityTextMaterial.popupTitle,
                  ),
                  SizedBox(height: ux(context, 24)),

                  // Campaign / Bonus Tab Switcher
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: ux(context, 12)),
                    decoration: BoxDecoration(
                      color: const Color(0xFF061E6E),
                      borderRadius: BorderRadius.circular(ux(context, 36)),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: const Color(0xFF2874FA),
                        borderRadius: BorderRadius.circular(ux(context, 32)),
                      ),
                      labelStyle: TextStyle(
                        fontFamily: 'Baloo2',
                        fontSize: ux(context, 42),
                        fontWeight: FontWeight.w800,
                        fontVariations: const [FontVariation('wght', 800)],
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF9AC0FF),
                      tabs: [
                        Tab(text: 'Campaign (${campaign.length})'),
                        Tab(text: 'Bonus (${bonus.length})'),
                      ],
                    ),
                  ),
                  SizedBox(height: ux(context, 22)),

                  // White `Panel_Popup.png` scrollable well
                  Expanded(
                    child: UnityNineSlice(
                      sprite: 'Panel_Popup.png',
                      width: double.infinity,
                      padding: EdgeInsets.all(ux(context, 24)),
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          // 1. All 121 Campaign Levels
                          GridView.builder(
                            padding: EdgeInsets.all(ux(context, 10)),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: ux(context, 22),
                              crossAxisSpacing: ux(context, 22),
                              childAspectRatio: 0.94,
                            ),
                            itemCount: campaign.length,
                            itemBuilder: (context, index) {
                              final lv = campaign[index];
                              final isCurrent = !widget.activeIsBonus &&
                                  widget.activeLevelNumber == lv.number;
                              final sprite = isCurrent
                                  ? 'Button_CTA.png'
                                  : 'Button_Blue.png';
                              final textMat = isCurrent
                                  ? UnityTextMaterial.ctaGreen
                                  : UnityTextMaterial.ctaBlue;

                              return GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onSelectLevel(lv);
                                },
                                child: UnityNineSlice(
                                  sprite: sprite,
                                  padding: EdgeInsets.only(bottom: ux(context, 10)),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      UnitySdfText(
                                        '${lv.number}',
                                        unityFontSize: 60,
                                        material: textMat,
                                      ),
                                      Text(
                                        '${lv.cols}×${lv.rows}',
                                        style: TextStyle(
                                          fontFamily: 'Baloo2',
                                          fontSize: ux(context, 28),
                                          fontWeight: FontWeight.w700,
                                          fontVariations: const [
                                            FontVariation('wght', 700),
                                          ],
                                          color: Colors.white.withValues(alpha: 0.9),
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          // 2. 25 Bonus Levels
                          ListView.separated(
                            padding: EdgeInsets.all(ux(context, 10)),
                            itemCount: bonus.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: ux(context, 18)),
                            itemBuilder: (context, index) {
                              final lv = bonus[index];
                              final isCurrent = widget.activeIsBonus &&
                                  widget.activeLevelNumber == lv.number;
                              return UnityCtaButton(
                                skin: isCurrent
                                    ? UnityButtonSkin.green
                                    : UnityButtonSkin.blue,
                                label: '${lv.title} (${lv.cols}×${lv.rows})',
                                unityWidth: 780,
                                unityHeight: 136,
                                unityFontSize: 52,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onSelectLevel(lv);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top-Right `Button_Close.png`
          Positioned(
            top: 0,
            right: ux(context, 14),
            child: UnitySpriteButton(
              asset: 'Button_Close.png',
              unitySize: 138,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
