import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import '../app_colors.dart';
import '../services/sms_loader_service.dart';
import '../services/sms_export_service.dart';
import '../services/transaction_service.dart';
import '../theme_decorations.dart';
import 'terms_page.dart';

class MoreTabPage extends StatefulWidget {
  final bool isPublic;
  final bool isTogglingPublic;
  final ValueChanged<bool> onPublicChanged;
  final List<SmsMessage> messages;
  final ValueChanged<List<SmsMessage>>? onMessagesRefreshed;

  const MoreTabPage({
    super.key,
    required this.isPublic,
    required this.isTogglingPublic,
    required this.onPublicChanged,
    this.messages = const [],
    this.onMessagesRefreshed,
  });

  @override
  State<MoreTabPage> createState() => _MoreTabPageState();
}

class _MoreTabPageState extends State<MoreTabPage> {
  bool _exportingSms = false;
  bool _refreshingSms = false;

  Future<void> _refreshSmsAndSync() async {
    if (_refreshingSms) return;
    setState(() => _refreshingSms = true);

    final c = Theme.of(context).extension<AppColors>()!;

    try {
      final messages = await SmsLoaderService.loadMMoneyInbox();
      if (messages.isEmpty) {
        throw StateError('No M-Money SMS found on this device.');
      }

      widget.onMessagesRefreshed?.call(messages);
      await TransactionService().ingestSmsMessages(messages);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.success,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Reloaded ${messages.length} SMS and synced to Firestore.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.danger,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Refresh failed: $e',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshingSms = false);
    }
  }

  Future<void> _exportSms() async {
    if (_exportingSms) return;
    setState(() => _exportingSms = true);

    final c = Theme.of(context).extension<AppColors>()!;

    try {
      final file = await SmsExportService().exportToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.success,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Exported to ${file.path}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.danger,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Export failed: $e',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingSms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Settings',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Privacy, appearance, and legal',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          child: SwitchListTile(
            value: widget.isPublic,
            onChanged: widget.isTogglingPublic ? null : widget.onPublicChanged,
            secondary: Icon(
              widget.isPublic ? Icons.public_rounded : Icons.lock_rounded,
              color: widget.isPublic ? c.success : c.textSecondary,
            ),
            title: Text(
              'Public profile',
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              widget.isPublic
                  ? 'Monthly totals are visible on the leaderboard and compare tab.'
                  : 'Only you can see your data. Turn on to compare with others.',
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
            activeThumbColor: c.primary,
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: _SettingsTile(
            icon: Icons.sync_rounded,
            iconColor: c.success,
            title: 'Refresh SMS & sync',
            subtitle: _refreshingSms
                ? 'Reloading inbox...'
                : 'Re-read all M-Money SMS and update Firestore totals',
            onTap: _refreshingSms ? () {} : _refreshSmsAndSync,
            showChevron: !_refreshingSms,
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: _SettingsTile(
            icon: Icons.sms_outlined,
            iconColor: c.primary,
            title: 'Export SMS',
            subtitle: _exportingSms
                ? 'Exporting...'
                : 'Save M-Money & ${SmsExportService.defaultPhone} SMS to Downloads',
            onTap: _exportingSms ? () {} : _exportSms,
            showChevron: !_exportingSms,
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                iconColor: c.primary,
                title: isDark ? 'Light mode' : 'Dark mode',
                subtitle: 'Switch app theme',
                onTap: () {
                  themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              Divider(height: 1, color: c.cardBorder.withValues(alpha: 0.5)),
              _SettingsTile(
                icon: Icons.gavel_rounded,
                iconColor: c.textSecondary,
                title: 'Terms & conditions',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TermsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: c.accentPurple,
            title: 'About',
            subtitle: 'M-Money transaction dashboard',
            onTap: () {},
            showChevron: false,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Container(
      decoration: AppDecorations.card(c, context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            )
          : null,
      trailing: showChevron
          ? Icon(Icons.chevron_right_rounded, color: c.textSecondary)
          : null,
    );
  }
}
