import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'string_property.dart';

const userAgreementVersion = '2026-10-24-v1';
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

  const UserAgreementContent({
    super.key,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.6);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final sections = <(String, String)>[
      (
        context.l10n.tr('1. 服务说明', en: '1. Service description'),
        context.l10n.tr(
          '本应用是非官方修改版，与内容平台及上游项目维护者无隶属关系。应用依赖第三方网络服务，其可用性、内容和规则可能随时变化。',
          en: 'This is an unofficial modified app and is not affiliated with the content platform or upstream maintainers. It relies on third-party services whose availability, content, and rules may change.',
        ),
      ),
      (
        context.l10n.tr('2. 本地数据与网络连接', en: '2. Local data and network'),
        context.l10n.tr(
          '书架、阅读记录、下载设置等主要保存在本机。登录、评论、WebDAV 同步和使用网络服务时，相关数据会发送到您选择或应用连接的服务器，并受对应服务的规则约束。',
          en: 'Bookshelf, reading history, and download settings are primarily stored on this device. Login, comments, WebDAV sync, and network services may send related data to servers you choose or the app connects to, subject to their rules.',
        ),
      ),
      (
        context.l10n.tr('3. 存储与下载', en: '3. Storage and downloads'),
        context.l10n.tr(
          '应用会在本机保存缓存、漫画文件和更新安装包。请在系统权限提示中确认用途后再授权；您可以随时在系统设置中撤销权限或清理应用数据。',
          en: 'The app stores cache, comic files, and update packages locally. Review system permission prompts before granting access. You can revoke permissions or clear app data in system settings.',
        ),
      ),
      (
        context.l10n.tr('4. 内容与使用规范', en: '4. Content and usage'),
        context.l10n.tr(
          '请遵守所在地法律法规及内容版权要求，不得利用本应用传播违法内容或侵犯他人权益。请勿将内容资产用于商业传播或未经授权的再分发。',
          en: 'Comply with local laws and content rights. Do not use the app to distribute illegal content or infringe others’ rights. Do not commercially redistribute content assets without authorization.',
        ),
      ),
      (
        context.l10n.tr('5. 安全与更新', en: '5. Security and updates'),
        context.l10n.tr(
          '应更新仅从本项目 GitHub Release 获取。应用会校验安装包地址、文件大小、SHA-256 和包名；系统仍会显示最终的安装确认页面。',
          en: 'App updates are obtained only from this project’s GitHub Releases. The app verifies the URL, file size, SHA-256, and package name; the system installer still displays the final confirmation.',
        ),
      ),
      (
        context.l10n.tr('6. 风险与协议更新', en: '6. Risks and changes'),
        context.l10n.tr(
          '第三方服务中断、内容变化、设备兼容性或网络环境可能影响使用。协议发生重要更新时会重新展示；继续使用前需要再次确认。不同意本协议时请退出应用。',
          en: 'Third-party outages, content changes, device compatibility, or network conditions may affect use. Important agreement updates will be shown again and require confirmation. Exit the app if you do not agree.',
        ),
      ),
    ];
    return Padding(
      padding: padding,
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.tr(
                '请在使用前阅读以下内容。点击“同意并继续”表示您已理解并接受本协议。',
                en: 'Please read the following before use. Selecting “Agree and continue” confirms that you understand and accept these terms.',
              ),
              style: bodyStyle?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            for (var index = 0; index < sections.length; index++) ...[
              Text(sections[index].$1, style: titleStyle),
              const SizedBox(height: 6),
              Text(sections[index].$2, style: bodyStyle),
              if (index != sections.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
