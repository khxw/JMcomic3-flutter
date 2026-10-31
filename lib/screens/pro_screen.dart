import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/is_pro.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'access_key_replace_screen.dart';
import 'components/app_back_button.dart';
import 'components/pro_center_ui.dart';
import 'components/right_click_pop.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  String _username = '';

  @override
  void initState() {
    super.initState();
    methods.loadLastLoginUsername().then((value) {
      if (!mounted) return;
      setState(() => _username = value);
    });
    proEvent.subscribe(_setState);
  }

  @override
  void dispose() {
    proEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    return ProCenterBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: const AppBackButton(),
          title: Text(l10n.tr('发电中心', en: 'Support center')),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  ProCenterHeroCard(
                    username: _username,
                    active: isPro,
                    expiry: proCenterExpiryLabel(proInfoAf.expire),
                  ),
                  const SizedBox(height: 14),
                  _statusCard(context),
                  const SizedBox(height: 12),
                  ProCenterSectionCard(
                    icon: Icons.sync_rounded,
                    title: l10n.tr('同步发电状态', en: 'Refresh support status'),
                    subtitle: l10n.tr(
                      '重新获取账号当前的发电与会员信息',
                      en: 'Reload the current membership and support status',
                    ),
                    onTap: _refreshStatus,
                  ),
                  const SizedBox(height: 12),
                  ProCenterSectionCard(
                    icon: Icons.redeem_rounded,
                    title: l10n.tr('兑换礼物卡', en: 'Redeem gift code'),
                    subtitle: l10n.tr(
                      '输入作者提供的兑换代码',
                      en: 'Enter the gift code provided by the author',
                    ),
                    onTap: _redeemCode,
                  ),
                  const SizedBox(height: 12),
                  const ProCenterServerCard(),
                  const SizedBox(height: 12),
                  _patCard(context),
                  const SizedBox(height: 12),
                  _guideCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final l10n = context.l10n;
    return ProCenterSectionCard(
      icon: Icons.verified_user_outlined,
      title: l10n.tr('会员状态', en: 'Membership status'),
      child: Column(
        children: [
          ProCenterInfoRow(
            icon: Icons.person_outline_rounded,
            label: l10n.tr('登录兑换', en: 'Account'),
            value: proInfoAf.isPro
                ? l10n.tr('发电中', en: 'Active')
                : l10n.tr('未发电', en: 'Inactive'),
            valueColor:
                proInfoAf.isPro ? Theme.of(context).colorScheme.primary : null,
          ),
          const Divider(height: 1),
          ProCenterInfoRow(
            icon: Icons.vpn_key_outlined,
            label: l10n.tr('PAT会员', en: 'PAT'),
            value: proInfoPat.isPro
                ? l10n.tr('发电中', en: 'Active')
                : l10n.tr('未发电', en: 'Inactive'),
            valueColor: proInfoPat.isPro
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }

  Widget _patCard(BuildContext context) {
    final l10n = context.l10n;
    final configured = proInfoPat.accessKey.isNotEmpty;
    final status = _patStatus(context);
    return ProCenterSectionCard(
      icon: Icons.key_rounded,
      title: l10n.tr('PAT 会员', en: 'PAT membership'),
      subtitle: configured
          ? l10n.tr('已记录授权密钥', en: 'Authorization key saved')
          : l10n.tr(
              '绑定 PAT 授权码以同步会员状态',
              en: 'Bind a PAT key to sync membership status',
            ),
      trailing: configured ? _statusBadge(context, status) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (configured) ...[
            if (proInfoPat.patId.isNotEmpty)
              ProCenterInfoRow(
                icon: Icons.badge_outlined,
                label: l10n.tr('PAT账号', en: 'PAT account'),
                value: proInfoPat.patId,
              ),
            if (proInfoPat.bindUid.isNotEmpty)
              ProCenterInfoRow(
                icon: Icons.link_rounded,
                label: l10n.tr('绑定账号', en: 'Bound account'),
                value: proInfoPat.bindUid,
              ),
            if (proInfoPat.reBind > 0)
              ProCenterInfoRow(
                icon: Icons.schedule_rounded,
                label: l10n.tr('可重绑时间', en: 'Rebind available'),
                value: _formatTimestamp(proInfoPat.reBind),
              ),
            if (proInfoPat.requestDelete > 0)
              ProCenterInfoRow(
                icon: Icons.event_busy_outlined,
                label: l10n.tr('解绑时间', en: 'Unbind time'),
                value: _formatTimestamp(proInfoPat.requestDelete),
              ),
          ] else
            Text(
              l10n.tr(
                'PAT 密钥仅保存在本机与账号同步配置中，不会显示完整密钥内容。',
                en: 'The PAT key is stored locally and in your account sync settings. The full key is never displayed.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: configured ? _managePat : _addPatAccount,
            icon: Icon(configured ? Icons.manage_accounts : Icons.add_rounded),
            label: Text(
              configured
                  ? l10n.tr('管理 PAT', en: 'Manage PAT')
                  : l10n.tr('绑定 PAT 授权码', en: 'Bind PAT key'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideCard(BuildContext context) {
    final l10n = context.l10n;
    return ProCenterSectionCard(
      icon: Icons.info_outline_rounded,
      title: l10n.tr('使用说明', en: 'How it works'),
      child: Column(
        children: [
          _guideRow(
            context,
            Icons.login_rounded,
            l10n.tr('先登录账号，再同步发电状态', en: 'Sign in before syncing status'),
          ),
          _guideRow(
            context,
            Icons.card_giftcard_rounded,
            l10n.tr('兑换作者提供的礼物卡', en: 'Redeem the author’s gift code'),
          ),
          _guideRow(
            context,
            Icons.route_rounded,
            l10n.tr('连接异常时可切换发电方式',
                en: 'Switch routes if the connection fails'),
          ),
          _guideRow(
            context,
            Icons.favorite_outline_rounded,
            l10n.tr('可从关于页支持项目维护',
                en: 'Support maintenance from the About page'),
          ),
        ],
      ),
    );
  }

  Widget _guideRow(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  ({String label, Color color}) _patStatus(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (proInfoPat.errorType > 0) {
      return (
        label: context.l10n.tr('状态异常', en: 'Error'),
        color: scheme.error,
      );
    }
    if (proInfoPat.bindUid.isEmpty) {
      return (
        label: context.l10n.tr('待绑定', en: 'Unbound'),
        color: scheme.tertiary,
      );
    }
    if (proInfoPat.bindUid != _username) {
      return (
        label: context.l10n.tr('已绑定其他账号', en: 'Other account'),
        color: scheme.error,
      );
    }
    if (!proInfoPat.isPro) {
      return (
        label: context.l10n.tr('未发电', en: 'Inactive'),
        color: scheme.tertiary,
      );
    }
    return (
      label: context.l10n.tr('状态正常', en: 'Active'),
      color: scheme.primary,
    );
  }

  Widget _statusBadge(
      BuildContext context, ({String label, Color color}) status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: status.color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Future<void> _refreshStatus() async {
    try {
      await methods.reloadPro();
      await reloadIsPro();
      if (!mounted) return;
      defaultToast(context, 'SUCCESS');
    } catch (error, stackTrace) {
      debugPrient('$error\n$stackTrace');
      if (!mounted) return;
      defaultToast(context, 'FAIL');
    }
  }

  Future<void> _redeemCode() async {
    final code = await displayTextInputDialog(
      context,
      title: context.l10n.tr('输入兑换代码', en: 'Enter gift code'),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await methods.inputCdKey(code.trim());
      await reloadIsPro();
      if (!mounted) return;
      defaultToast(context, 'SUCCESS');
    } catch (error, stackTrace) {
      debugPrient('$error\n$stackTrace');
      if (!mounted) return;
      defaultToast(context, 'FAIL');
    }
  }

  Future<void> _managePat() async {
    final choose = await chooseMapDialog<int>(
      context,
      title: context.l10n.tr('选择操作', en: 'Choose an action'),
      values: {
        context.l10n.tr('更新 PAT 状态', en: 'Refresh PAT status'): 2,
        context.l10n.tr('绑定到当前账号', en: 'Bind to current account'): 3,
        context.l10n.tr('更换 PAT 密钥', en: 'Replace PAT key'): 1,
        context.l10n.tr('清除 PAT 信息', en: 'Clear PAT information'): 4,
      },
    );
    switch (choose) {
      case 1:
        await _addPatAccount();
      case 2:
        await _reloadPatAccount();
      case 3:
        await _bindThisAccount();
      case 4:
        await _clearPatInfo();
    }
  }

  Future<void> _addPatAccount() async {
    final key = await displayTextInputDialog(
      context,
      title: context.l10n.tr('输入 PAT 授权码', en: 'Enter PAT key'),
    );
    if (key == null || key.trim().isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccessKeyReplaceScreen(accessKey: key.trim()),
      ),
    );
    await reloadIsPro();
    if (mounted) setState(() {});
  }

  Future<void> _reloadPatAccount() async {
    defaultToast(context, context.l10n.tr('请稍候', en: 'Please wait'));
    try {
      await methods.reloadPatAccount();
      await reloadIsPro();
      if (!mounted) return;
      defaultToast(context, 'SUCCESS');
    } catch (error) {
      if (!mounted) return;
      defaultToast(context, 'FAIL: $error');
    }
  }

  Future<void> _bindThisAccount() async {
    defaultToast(context, context.l10n.tr('请稍候', en: 'Please wait'));
    try {
      await methods.bindPatAccount(proInfoPat.accessKey, _username);
      await methods.reloadPatAccount();
      await reloadIsPro();
      if (!mounted) return;
      defaultToast(context, 'SUCCESS');
    } catch (error) {
      if (!mounted) return;
      defaultToast(context, 'FAIL: $error');
    }
  }

  Future<void> _clearPatInfo() async {
    await methods.clearPat();
    await reloadIsPro();
    if (!mounted) return;
    defaultToast(context, context.l10n.tr('已清除', en: 'Cleared'));
  }

  String _formatTimestamp(int seconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
