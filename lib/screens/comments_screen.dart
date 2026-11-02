import 'package:flutter/material.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/app_back_button.dart';
import 'components/comic_comments_list.dart';
import 'components/right_click_pop.dart';

class CommentsScreen extends StatefulWidget {
  const CommentsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen>
    with SingleTickerProviderStateMixin {
  var _idx = 0;
  late TabController _tabController;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.discussion),
      ),
      backgroundColor: scheme.surface,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .48),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: scheme.onPrimary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: theme.textTheme.labelMedium,
              onTap: (v) {
                setState(() {
                  _idx = v;
                });
              },
              tabs: [
                Tab(text: context.l10n.allComments),
                Tab(text: context.l10n.myComments),
              ],
            ),
          ),
        ),
        Expanded(
          child: _idx == 0
              ? const ComicCommentsList(
                  mode: "manhua",
                  aid: null,
                  gotoComic: true,
                  scrollable: true,
                )
              : const SelfCommentList(),
        ),
      ],
    );
  }
}

class SelfCommentList extends StatefulWidget {
  const SelfCommentList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SelfCommentListState();
}

class _SelfCommentListState extends State<SelfCommentList> {
  @override
  void initState() {
    loginEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loginStatus == LoginStatus.loginSuccess) {
      return ComicCommentsList(
        mode: "manhua",
        aid: null,
        gotoComic: true,
        uid: selfInfo.uid,
        scrollable: true,
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.tipLoginRequired,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.tipMyCommentsNeedLogin,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                await ensureJwtAccess(
                  context,
                  feature: context.l10n.tipMyCommentsNeedLogin,
                );
              },
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(context.l10n.goLogin),
            ),
          ],
        ),
      ),
    );
  }
}
