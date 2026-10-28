import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'string_property.dart';

const userAgreementVersion = '2026-10-24-v3';
const _userAgreementProperty = 'accepted_user_agreement_version';

Future<bool> hasAcceptedCurrentUserAgreement() async {
  final value = await methods.loadProperty(_userAgreementProperty);
  return parseStringPropertyValue(value, trim: true) == userAgreementVersion;
}

Future<void> acceptCurrentUserAgreement() {
  return methods.saveProperty(_userAgreementProperty, userAgreementVersion);
}

class UserAgreementContent extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final bool showIntro;

  const UserAgreementContent({
    super.key,
    this.padding = EdgeInsets.zero,
    this.showIntro = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.6);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final sections = <(IconData, String, String)>[
      (
        Icons.verified_user_outlined,
        context.l10n.tr('服务说明', en: 'Service description'),
        context.l10n.tr(
          '本应用是非官方修改版，与内容平台及上游项目维护者无隶属关系。应用依赖第三方网络服务，其可用性、内容、账号规则和访问策略可能随时调整。',
          en: 'This is an unofficial modified app and is not affiliated with the content platform or upstream maintainers. It relies on third-party services whose availability, content, account rules, and access policies may change.',
        ),
      ),
      (
        Icons.phone_android_rounded,
        context.l10n.tr('本地数据', en: 'Local data'),
        context.l10n.tr(
          '书架、阅读记录、分组、主题和下载设置主要保存在本机；游客状态下也可以使用本地书架和基础阅读功能。您可以随时在系统设置中清理应用数据。',
          en: 'Bookshelf, reading history, groups, themes, and download settings are primarily stored on this device. Local library and basic reading features remain available in guest mode. You can clear app data in system settings at any time.',
        ),
      ),
      (
        Icons.sync_rounded,
        context.l10n.tr('账号、网络与同步', en: 'Account, network, and sync'),
        context.l10n.tr(
          '仅在您主动登录、发表评论或启用 WebDAV 同步时，相关账号和操作数据才会发送到对应服务或您配置的服务器。这些数据由相应服务处理，请同时阅读其隐私规则。',
          en: 'Account and activity data is sent only when you sign in, post comments, or enable WebDAV sync. It is sent to the corresponding service or your configured server and is subject to that service’s privacy rules.',
        ),
      ),
      (
        Icons.gavel_rounded,
        context.l10n.tr('内容与使用规范', en: 'Content and usage'),
        context.l10n.tr(
          '请确认您对访问和下载的内容拥有合法权限，并遵守所在地法律法规及内容版权要求。不得传播违法内容、侵犯他人权益，或将内容资产用于未经授权的商业传播和再分发。',
          en: 'Ensure you have lawful access to viewed and downloaded content and comply with local laws and content rights. Do not distribute illegal content, infringe others’ rights, or commercially redistribute content assets without authorization.',
        ),
      ),
      (
        Icons.folder_copy_outlined,
        context.l10n.tr('存储与下载', en: 'Storage and downloads'),
        context.l10n.tr(
          '缓存、漫画文件和更新安装包会占用本机存储。申请存储权限前，系统会说明用途；自定义下载目录需要您主动授权。请定期清理不需要的内容，并确保设备有足够空间。',
          en: 'Cache, comic files, and update packages use local storage. System prompts explain storage access before permission is granted, and custom download folders require your approval. Clean unneeded content and keep enough free space.',
        ),
      ),
      (
        Icons.system_update_alt_rounded,
        context.l10n.tr('更新与安全', en: 'Updates and security'),
        context.l10n.tr(
          '应用内更新来自本项目 GitHub Release 或其中转镜像，镜像仅在取得 SHA-256 后启用；应用会校验文件大小、SHA-256 和应用包名。最终是否安装仍由 Android 系统安装器确认；请勿安装来源不明的 APK。',
          en: 'In-app updates come from this project’s GitHub Releases or relay mirrors, which are enabled only when a SHA-256 is available. The app verifies file size, SHA-256, and package name. Android’s system installer still confirms the final installation; do not install APKs from untrusted sources.',
        ),
      ),
    ];
    return Padding(
      padding: padding,
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showIntro) ...[
              Container(
                key: const ValueKey('agreement-summary-card'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .16),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 21,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.tr(
                          '重点提示：书架和阅读记录主要保存在本机；登录、评论和同步仅在对应功能启用时连接第三方服务。请遵守当地法律与内容版权要求。',
                          en: 'Key points: bookshelf and reading history are primarily stored locally. Login, comments, and sync connect to third-party services only when those features are used. Follow local law and content rights.',
                        ),
                        style: bodyStyle?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            for (var index = 0; index < sections.length; index++) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${index + 1}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Icon(
                          sections[index].$1,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            sections[index].$2,
                            style: titleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(sections[index].$3, style: bodyStyle),
                  ],
                ),
              ),
              if (index != sections.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
