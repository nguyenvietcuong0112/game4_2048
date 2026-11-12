import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/level_models.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// Compact floating/footer developer button (`🛠 CHEAT`) shown ONLY when
/// `RemoteConfigService.cheatEnable == true`.
class CheatHudButton extends StatefulWidget {
  final VoidCallback onTap;

  const CheatHudButton({
    super.key,
    required this.onTap,
  });

  @override
  State<CheatHudButton> createState() => _CheatHudButtonState();
}

class _CheatHudButtonState extends State<CheatHudButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ux(context, 22),
            vertical: ux(context, 14),
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xE61E293B),
                Color(0xF20F172A),
              ],
            ),
            borderRadius: BorderRadius.circular(ux(context, 40)),
            border: Border.all(
              color: const Color(0xFFFFB715),
              width: ux(context, 4.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: ux(context, 12),
                offset: Offset(0, ux(context, 4)),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_fix_high_rounded,
                size: ux(context, 36),
                color: const Color(0xFFFFD233),
              ),
              SizedBox(width: ux(context, 8)),
              Text(
                'CHEAT',
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontSize: ux(context, 32),
                  fontWeight: FontWeight.w800,
                  fontVariations: const [FontVariation('wght', 800)],
                  color: Colors.white,
                  letterSpacing: 0.6,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Comprehensive Developer / QA Cheat Panel gated by `RemoteConfigService.cheatEnable` (`cheat_enable`).
class CheatPanelOverlay extends StatefulWidget {
  final LevelDefinition activeLevel;
  final LevelRepository repository;
  final PlayerProgressService progress;
  final int remainingSeconds;
  final bool hideHudButton;
  final ValueChanged<bool> onToggleHideHudButton;
  final ValueChanged<LevelDefinition> onJumpToLevel;
  final VoidCallback onInstantWinPopup;
  final VoidCallback onWinWithSandSequence;
  final VoidCallback onInstantLoseTimeout;
  final VoidCallback onMergeOnePairFree;
  final VoidCallback onUnlockAllBoardObstacles;
  final VoidCallback onTriggerComboStep;
  final ValueChanged<int> onAddTimeSeconds;
  final ValueChanged<int> onSetTimeSeconds;
  final VoidCallback onTriggerFreeTimeFreeze;
  final Future<void> Function() onResetAllProgress;
  final VoidCallback onClose;

  const CheatPanelOverlay({
    super.key,
    required this.activeLevel,
    required this.repository,
    required this.progress,
    required this.remainingSeconds,
    required this.hideHudButton,
    required this.onToggleHideHudButton,
    required this.onJumpToLevel,
    required this.onInstantWinPopup,
    required this.onWinWithSandSequence,
    required this.onInstantLoseTimeout,
    required this.onMergeOnePairFree,
    required this.onUnlockAllBoardObstacles,
    required this.onTriggerComboStep,
    required this.onAddTimeSeconds,
    required this.onSetTimeSeconds,
    required this.onTriggerFreeTimeFreeze,
    required this.onResetAllProgress,
    required this.onClose,
  });

  @override
  State<CheatPanelOverlay> createState() => _CheatPanelOverlayState();
}

class _CheatPanelOverlayState extends State<CheatPanelOverlay> {
  late final TextEditingController _levelInputCtrl;
  bool _showBonusList = false;

  int get _maxCampaignLevel => widget.repository.campaignLevels.length;

  @override
  void initState() {
    super.initState();
    _showBonusList = widget.activeLevel.isBonus;
    _levelInputCtrl = TextEditingController(
      text: widget.activeLevel.isBonus
          ? '${widget.progress.currentLevel}'
          : '${widget.activeLevel.number}',
    );
  }

  @override
  void didUpdateWidget(covariant CheatPanelOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeLevel.number != widget.activeLevel.number) {
      if (widget.activeLevel.isBonus) {
        _showBonusList = true;
      } else {
        _levelInputCtrl.text = '${widget.activeLevel.number}';
      }
    }
  }

  @override
  void dispose() {
    _levelInputCtrl.dispose();
    super.dispose();
  }

  void _jumpToCampaignLevel(int targetLevel) {
    FocusManager.instance.primaryFocus?.unfocus();
    final clamped = targetLevel.clamp(1, _maxCampaignLevel);
    final lv = widget.repository.getCampaignLevel(clamped);
    widget.onJumpToLevel(lv);
  }

  void _stepActiveLevel(int delta) {
    FocusManager.instance.primaryFocus?.unfocus();
    final bonusList = widget.repository.bonusLevels;
    if (widget.activeLevel.isBonus && bonusList.isNotEmpty) {
      final curIdx = bonusList.indexWhere(
        (b) => b.number == widget.activeLevel.number,
      );
      final baseIdx = curIdx >= 0 ? curIdx : 0;
      final nextIdx =
          (baseIdx + delta) % bonusList.length < 0
              ? ((baseIdx + delta) % bonusList.length) + bonusList.length
              : (baseIdx + delta) % bonusList.length;
      widget.onJumpToLevel(bonusList[nextIdx]);
      return;
    }
    _jumpToCampaignLevel(widget.activeLevel.number + delta);
  }

  void _handleGoTypedLevel() {
    FocusManager.instance.primaryFocus?.unfocus();
    final parsed = int.tryParse(_levelInputCtrl.text.trim());
    if (parsed == null) return;
    _jumpToCampaignLevel(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final kbBottom = MediaQuery.viewInsetsOf(context).bottom;
    final availHeight =
        (MediaQuery.sizeOf(context).height - kbBottom).clamp(220.0, 4000.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        widget.onClose();
      },
      child: Container(
        color: const Color(0xCC070416),
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: kbBottom),
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ux(context, 960),
                    maxHeight: availHeight * 0.86,
                  ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: ux(context, 36)),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(ux(context, 42)),
                      border: Border.all(
                        color: const Color(0xFFFFB715),
                        width: ux(context, 5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: ux(context, 36),
                          offset: Offset(0, ux(context, 14)),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(context),
                        Flexible(
                          child: ListenableBuilder(
                            listenable: widget.progress,
                            builder: (context, _) {
                              return SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  ux(context, 32),
                                  ux(context, 20),
                                  ux(context, 32),
                                  ux(context, 32),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildLevelJumpSection(context),
                                    SizedBox(height: ux(context, 24)),
                                    _buildBoardAndOutcomeSection(context),
                                    SizedBox(height: ux(context, 24)),
                                    _buildTimerSection(context),
                                    SizedBox(height: ux(context, 24)),
                                    _buildEconomySection(context),
                                    SizedBox(height: ux(context, 24)),
                                    _buildSystemSection(context),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ux(context, 28),
        vertical: ux(context, 20),
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ux(context, 14),
              vertical: ux(context, 6),
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(ux(context, 16)),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Text(
              'RC: cheat_enable',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ux(context, 24),
                fontWeight: FontWeight.w800,
                color: const Color(0xFF34D399),
              ),
            ),
          ),
          SizedBox(width: ux(context, 14)),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'CHEAT / QA PANEL',
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontSize: ux(context, 40),
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
          SizedBox(width: ux(context, 12)),
          IconButton(
            key: const ValueKey('cheat_close_btn'),
            onPressed: widget.onClose,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              Icons.close_rounded,
              size: ux(context, 52),
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelJumpSection(BuildContext context) {
    final bonusLevels = widget.repository.bonusLevels;
    final isBonus = widget.activeLevel.isBonus;
    return _CheatSectionCard(
      title: isBonus
          ? '1. Chuyển Level (Đang chơi Bonus: ${widget.activeLevel.title})'
          : '1. Chuyển Level (${widget.activeLevel.title} / $_maxCampaignLevel màn)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _CheatActionBtn(
                label: '-10',
                compact: true,
                color: const Color(0xFF334155),
                onTap: () => _stepActiveLevel(-10),
              ),
              SizedBox(width: ux(context, 8)),
              _CheatActionBtn(
                label: '-1',
                compact: true,
                color: const Color(0xFF334155),
                onTap: () => _stepActiveLevel(-1),
              ),
              SizedBox(width: ux(context, 10)),
              Expanded(
                child: SizedBox(
                  height: ux(context, 78),
                  child: TextField(
                    key: const ValueKey('cheat_level_input'),
                    controller: _levelInputCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontSize: ux(context, 38),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      hintText: 'Lv #',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ux(context, 18)),
                        borderSide: const BorderSide(color: Color(0xFF475569)),
                      ),
                    ),
                    onSubmitted: (_) => _handleGoTypedLevel(),
                  ),
                ),
              ),
              SizedBox(width: ux(context, 10)),
              _CheatActionBtn(
                key: const ValueKey('cheat_level_go_btn'),
                label: 'GO',
                compact: true,
                color: const Color(0xFF2563EB),
                onTap: _handleGoTypedLevel,
              ),
              SizedBox(width: ux(context, 8)),
              _CheatActionBtn(
                label: '+1',
                compact: true,
                color: const Color(0xFF334155),
                onTap: () => _stepActiveLevel(1),
              ),
              SizedBox(width: ux(context, 8)),
              _CheatActionBtn(
                label: '+10',
                compact: true,
                color: const Color(0xFF334155),
                onTap: () => _stepActiveLevel(10),
              ),
            ],
          ),
          SizedBox(height: ux(context, 16)),
          Wrap(
            spacing: ux(context, 12),
            runSpacing: ux(context, 12),
            children: [
              _CheatChip(
                label: 'Lv 1 (Tut)',
                onTap: () => _jumpToCampaignLevel(1),
              ),
              _CheatChip(
                label: 'Lv 2 (Old Lv1)',
                onTap: () => _jumpToCampaignLevel(2),
              ),
              _CheatChip(
                label: 'Lv 6 (Ice)',
                onTap: () => _jumpToCampaignLevel(6),
              ),
              _CheatChip(
                label: 'Lv 16 (Dud)',
                onTap: () => _jumpToCampaignLevel(16),
              ),
              _CheatChip(
                label: 'Lv 17 (Unlock LvUp)',
                onTap: () => _jumpToCampaignLevel(17),
              ),
              _CheatChip(
                label: 'Lv 27 (Unlock Freeze)',
                onTap: () => _jumpToCampaignLevel(27),
              ),
              _CheatChip(
                label: 'Lv 50',
                onTap: () => _jumpToCampaignLevel(50),
              ),
            ],
          ),
          if (bonusLevels.isNotEmpty) ...[
            SizedBox(height: ux(context, 18)),
            Row(
              children: [
                Expanded(
                  child: _CheatActionBtn(
                    key: const ValueKey('cheat_toggle_bonus_list_btn'),
                    label: _showBonusList
                        ? '▲ Ẩn Danh Sách Màn Bonus (${bonusLevels.length} màn)'
                        : '🎁 Mở Toàn Bộ Level Bonus (${bonusLevels.length} màn)',
                    color: const Color(0xFF7C3AED),
                    onTap: () => setState(() => _showBonusList = !_showBonusList),
                  ),
                ),
                if (isBonus) ...[
                  SizedBox(width: ux(context, 12)),
                  _CheatActionBtn(
                    label: '↩ Lv ${widget.progress.currentLevel}',
                    compact: true,
                    color: const Color(0xFF0284C7),
                    onTap: () =>
                        _jumpToCampaignLevel(widget.progress.currentLevel),
                  ),
                ],
              ],
            ),
            if (_showBonusList) ...[
              SizedBox(height: ux(context, 16)),
              Container(
                padding: EdgeInsets.all(ux(context, 16)),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(ux(context, 22)),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.6),
                  ),
                ),
                child: Wrap(
                  spacing: ux(context, 12),
                  runSpacing: ux(context, 12),
                  children: [
                    for (int i = 0; i < bonusLevels.length; i++)
                      _buildBonusLevelChip(context, i, bonusLevels[i]),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBonusLevelChip(
    BuildContext context,
    int index,
    LevelDefinition bonusLv,
  ) {
    final selected = widget.activeLevel.isBonus &&
        widget.activeLevel.number == bonusLv.number;
    return Material(
      color: selected ? const Color(0xFF7C3AED) : const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(ux(context, 18)),
      child: InkWell(
        key: ValueKey('cheat_bonus_lv_${index + 1}'),
        borderRadius: BorderRadius.circular(ux(context, 18)),
        onTap: () => widget.onJumpToLevel(bonusLv),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ux(context, 18),
            vertical: ux(context, 12),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ux(context, 18)),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFF475569),
              width: selected ? ux(context, 2.5) : 1.0,
            ),
          ),
          child: Text(
            '#${index + 1}: ${bonusLv.title}',
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontSize: ux(context, 27),
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFFE2E8F0),
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardAndOutcomeSection(BuildContext context) {
    return _CheatSectionCard(
      title: '2. Kết quả & Hỗ trợ Bàn chơi',
      child: Wrap(
        spacing: ux(context, 14),
        runSpacing: ux(context, 14),
        children: [
          _CheatActionBtn(
            key: const ValueKey('cheat_win_now_btn'),
            label: 'Thắng Ngay (Popup)',
            color: const Color(0xFF059669),
            onTap: widget.onInstantWinPopup,
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_win_sand_btn'),
            label: 'Thắng + FX Cát',
            color: const Color(0xFF0D9488),
            onTap: widget.onWinWithSandSequence,
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_lose_now_btn'),
            label: 'Thua Ngay (Hết giờ)',
            color: const Color(0xFFDC2626),
            onTap: widget.onInstantLoseTimeout,
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_merge_pair_btn'),
            label: 'Gộp 1 Cặp Free',
            color: const Color(0xFF2563EB),
            onTap: widget.onMergeOnePairFree,
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_unlock_board_btn'),
            label: 'Phá Băng & Mở Khóa',
            color: const Color(0xFF7C3AED),
            onTap: widget.onUnlockAllBoardObstacles,
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_combo_step_btn'),
            label: '+1 Combo Bar',
            color: const Color(0xFFD97706),
            onTap: widget.onTriggerComboStep,
          ),
        ],
      ),
    );
  }

  Widget _buildTimerSection(BuildContext context) {
    return _CheatSectionCard(
      title: '3. Thời gian (Hiện tại: ${widget.remainingSeconds}s)',
      child: Wrap(
        spacing: ux(context, 14),
        runSpacing: ux(context, 14),
        children: [
          _CheatActionBtn(
            label: '+30 Giây',
            color: const Color(0xFF0284C7),
            onTap: () => widget.onAddTimeSeconds(30),
          ),
          _CheatActionBtn(
            label: '+60 Giây',
            color: const Color(0xFF0284C7),
            onTap: () => widget.onAddTimeSeconds(60),
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_timer_5s_btn'),
            label: 'Còn 5s (Test Urgent)',
            color: const Color(0xFFE11D48),
            onTap: () => widget.onSetTimeSeconds(5),
          ),
          _CheatActionBtn(
            label: 'Đóng Băng 20s Free',
            color: const Color(0xFF0891B2),
            onTap: widget.onTriggerFreeTimeFreeze,
          ),
        ],
      ),
    );
  }

  Widget _buildEconomySection(BuildContext context) {
    final p = widget.progress;
    return _CheatSectionCard(
      title:
          '4. Tài nguyên (Coins: ${p.coins} | LvUp: ${p.levelUpCount} | Freeze: ${p.timeFreezeCount} | Mạng: ${p.lives})',
      child: Wrap(
        spacing: ux(context, 14),
        runSpacing: ux(context, 14),
        children: [
          _CheatActionBtn(
            key: const ValueKey('cheat_add_1k_coins_btn'),
            label: '+1,000 Coins',
            color: const Color(0xFFB45309),
            onTap: () => p.addCoins(1000),
          ),
          _CheatActionBtn(
            label: '+10,000 Coins',
            color: const Color(0xFFB45309),
            onTap: () => p.addCoins(10000),
          ),
          _CheatActionBtn(
            label: 'Coins = 0',
            color: const Color(0xFF475569),
            onTap: () => p.cheatSetCoins(0),
          ),
          _CheatActionBtn(
            key: const ValueKey('cheat_add_5_boosters_btn'),
            label: '+5 Mỗi Booster',
            color: const Color(0xFF4F46E5),
            onTap: () => p.cheatSetPowerUps(
              levelUp: p.levelUpCount + 5,
              timeFreeze: p.timeFreezeCount + 5,
            ),
          ),
          _CheatActionBtn(
            label: 'Boosters = 0',
            color: const Color(0xFF475569),
            onTap: () => p.cheatSetPowerUps(levelUp: 0, timeFreeze: 0),
          ),
          _CheatActionBtn(
            label: 'Mở Khóa Tất Cả Booster',
            color: const Color(0xFF059669),
            onTap: p.cheatUnlockAllBoostersAndMechanics,
          ),
          _CheatActionBtn(
            label: 'Full 5 Mạng',
            color: const Color(0xFFDB2777),
            onTap: () => p.cheatSetLives(PlayerProgressService.maxLives),
          ),
          _CheatActionBtn(
            label: 'Còn 1 Mạng',
            color: const Color(0xFF475569),
            onTap: () => p.cheatSetLives(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemSection(BuildContext context) {
    return _CheatSectionCard(
      title: '5. Hệ thống & Hiển thị',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Ẩn nút CHEAT nổi trên màn hình chơi',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ux(context, 34),
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              'Khi ẩn, bạn vẫn có thể mở lại bảng Cheat bằng cách mở Setting -> chạm vào dòng v.1.0.6',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ux(context, 26),
                color: Colors.white70,
              ),
            ),
            value: widget.hideHudButton,
            activeThumbColor: const Color(0xFFFFB715),
            onChanged: widget.onToggleHideHudButton,
          ),
          SizedBox(height: ux(context, 12)),
          _CheatActionBtn(
            label: 'Reset Toàn Bộ Dữ Liệu (Về Level 1)',
            color: const Color(0xFF991B1B),
            onTap: () async {
              await widget.onResetAllProgress();
            },
          ),
        ],
      ),
    );
  }
}

class _CheatSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _CheatSectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ux(context, 26)),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.10),
          width: ux(context, 2),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(ux(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ux(context, 34),
                fontWeight: FontWeight.w800,
                color: const Color(0xFFFFD233),
              ),
            ),
            SizedBox(height: ux(context, 16)),
            child,
          ],
        ),
      ),
    );
  }
}

class _CheatActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  const _CheatActionBtn({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(ux(context, 18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(ux(context, 18)),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ux(context, compact ? 15 : 24),
            vertical: ux(context, 16),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontSize: ux(context, compact ? 28 : 31),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _CheatChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CheatChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ux(context, 16)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ux(context, 20),
          vertical: ux(context, 10),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(ux(context, 16)),
          border: Border.all(color: const Color(0xFF475569)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Baloo2',
            fontSize: ux(context, 28),
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE2E8F0),
          ),
        ),
      ),
    );
  }
}
