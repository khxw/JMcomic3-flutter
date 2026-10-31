import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/is_pro.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/app_back_button.dart';
import 'components/pro_center_ui.dart';
import 'components/right_click_pop.dart';

class ProOhScreen extends StatefulWidget {
  const ProOhScreen({super.key});

  @override
  State<ProOhScreen> createState() => _ProOhScreenState();
}

class _ProOhScreenState extends State<ProOhScreen> {
  String _username = '';

  @override
  void initState() {
    super.initState();
    methods.loadLastLoginUsername().then((value) {
      if (!mounted) return;
      setState(() => _username = value);
    });
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
                    expiry: proCenterExpiryLabel(isProEx),
                  ),
                  const SizedBox(height: 14),
                  ProCenterSectionCard(
                    icon: Icons.verified_user_outlined,
                    title: l10n.tr('发电详情', en: 'Support details'),
                    child: ProCenterInfoRow(
                      icon: Icons.offline_bolt_outlined,
                      label: l10n.tr('当前状态', en: 'Status'),
                      value: isPro
                          ? l10n.tr('发电中', en: 'Active')
                          : l10n.tr('未发电', en: 'Inactive'),
                      valueColor: isPro
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProCenterSectionCard(
                    icon: Icons.sync_rounded,
                    title: l10n.tr('同步发电状态', en: 'Refresh support status'),
                    subtitle: l10n.tr(
                      '重新获取当前账号的发电信息',
                      en: 'Reload support information for this account',
                    ),
                    onTap: _refreshStatus,
                  ),
                  const SizedBox(height: 12),
                  const ProCenterServerCard(),
                ],
              ),
            ),
          ),
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
}
