import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/app_font_size.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/item_builder.dart';

import '../comic_info_screen.dart';
import 'app_back_button.dart';
import 'avatar.dart';
import 'text_preview_screen.dart';

class ComicCommentsList extends StatefulWidget {
  final String? mode;
  final int? aid;
  final int? uid;
  final bool gotoComic;
  final bool scrollable;

  const ComicCommentsList({
    required this.mode,
    required this.aid,
    this.uid,
    this.gotoComic = false,
    this.scrollable = false,
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicCommentsListState();
}

class _ComicCommentsListState extends State<ComicCommentsList> {
  late Future<CommentPage> _future;
  int _maxPage = 1;
  int _page = 1;

  Future<CommentPage> _loadPage() async {
    final response =
        await methods.forum(widget.mode, widget.aid, widget.uid, _page);
    if (_page == 1) {
      if (response.total == 0 || response.list.isEmpty) {
        _maxPage = 1;
      } else {
        _maxPage = (response.total / response.list.length).ceil();
      }
    }
    return response;
  }

  @override
  void initState() {
    _future = _loadPage();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ItemBuilder(
      future: _future,
      onRefresh: () async {
        setState(() {
          _future = _loadPage();
        });
      },
      successBuilder: (
        BuildContext context,
        AsyncSnapshot<CommentPage> snapshot,
      ) {
        final comments = snapshot.requireData.list;
        if (widget.scrollable) {
          return ListView.builder(
            key: const ValueKey('comments-scroll-list'),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            itemCount: comments.length + 3,
            itemBuilder: (context, index) {
              if (index == 0) return _buildPrePage();
              if (index <= comments.length) {
                return _buildComment(
                  context,
                  comments[index - 1],
                  true,
                  widget.mode,
                  widget.gotoComic,
                );
              }
              if (index == comments.length + 1) return _buildNextPage();
              if (widget.aid == null) return const SizedBox.shrink();
              return _buildPostComment(
                context,
                null,
                widget.aid!,
                () {
                  setState(() {
                    _future = _loadPage();
                  });
                },
              );
            },
          );
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPrePage(),
            ...comments.map((e) => _buildComment(
                  context,
                  e,
                  true,
                  widget.mode,
                  widget.gotoComic,
                )),
            _buildNextPage(),
            ...widget.aid != null
                ? [
                    _buildPostComment(
                      context,
                      null,
                      widget.aid!,
                      () {
                        setState(() {
                          _future = _loadPage();
                        });
                      },
                    ),
                  ]
                : [],
          ],
        );
      },
    );
  }

  Widget _buildPrePage() {
    if (_page > 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _page--;
                _future = _loadPage();
              });
            },
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: Text(context.l10n.tr('上一页', en: 'Previous')),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildNextPage() {
    if (_page < _maxPage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _page++;
                _future = _loadPage();
              });
            },
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: Text(context.l10n.tr('下一页', en: 'Next')),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

Widget _buildComment(
  BuildContext context,
  Comment comment,
  bool jumpList,
  String? mode,
  bool gotoComic,
) {
  return InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () {
      if (!jumpList) {
        return;
      }
      if (comment.AID != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _CommentChildrenScreen(
              aid: comment.AID!,
              mode: mode,
              comment: comment,
            ),
          ),
        );
      }
    },
    child: _ComicCommentItem(
      aid: comment.AID,
      mode: mode,
      comment: comment,
      gotoComic: jumpList && gotoComic,
    ),
  );
}

Widget _buildPostComment(
    BuildContext context, int? parentId, int aid, Function? f) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Material(
      color: scheme.primaryContainer.withValues(alpha: .42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: .18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _showCommentComposer(
            context,
            parentId: parentId,
            aid: aid,
            onPosted: f,
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 17,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  context.l10n.tr(
                    '写下你的评论...',
                    en: 'Write a comment...',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 19,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _showCommentComposer(
  BuildContext context, {
  required int? parentId,
  required int aid,
  required Function? onPosted,
}) async {
  if (!await ensureJwtAccess(
    context,
    feature: context.l10n.tr("发表评论", en: "Post comment"),
  )) {
    return;
  }
  final text = await displayTextInputDialog(
    context,
    title: context.l10n.tr('请输入评论内容', en: 'Enter your comment'),
  );
  if (text == null || text.isEmpty) return;
  try {
    final data = await (parentId == null
        ? methods.comment(aid, text)
        : methods.childComment(aid, text, parentId));
    if (!context.mounted) return;
    if (!data.isSuccess) {
      defaultToast(
        context,
        data.msg.isNotEmpty
            ? data.msg
            : context.l10n.tr("评论失败", en: "Comment failed"),
      );
      return;
    }
    defaultToast(context, context.l10n.tr("评论成功", en: "Comment posted"));
    onPosted?.call();
  } catch (e, st) {
    debugPrient("$e\n$st");
    if (context.mounted) {
      defaultToast(context, context.l10n.tr("评论失败", en: "Comment failed"));
    }
  }
}

class _ComicCommentItem extends StatefulWidget {
  // 清除缓存使用mode和aid
  final String? mode;
  final int? aid;
  final Comment comment;
  final bool gotoComic;

  const _ComicCommentItem({
    required this.mode,
    required this.aid,
    required this.comment,
    required this.gotoComic,
  });

  @override
  State<StatefulWidget> createState() => _ComicCommentItemState();
}

class _ComicCommentItemState extends State<_ComicCommentItem> {
  var likeLoading = false;
  late bool liked;
  var locallyLikedOnly = false;

  @override
  void initState() {
    liked = widget.comment.isLiked;
    if (!liked) {
      _restoreLocalLike();
    }
    super.initState();
  }

  Future<void> _restoreLocalLike() async {
    final likedIds = await methods.locallyLikedCommentIds();
    if (!mounted ||
        widget.comment.isLiked ||
        !likedIds.contains(widget.comment.CID)) {
      return;
    }
    setState(() {
      liked = true;
      locallyLikedOnly = true;
    });
  }

  Future<void> _likeComment() async {
    if (likeLoading || liked) return;
    if (!await ensureJwtAccess(
      context,
      feature: context.l10n.tr("评论点赞", en: "Like comment"),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      likeLoading = true;
    });
    try {
      final upstreamLimited = await methods.likeComment(widget.comment.CID);
      if (!mounted) return;
      setState(() {
        likeLoading = false;
        liked = true;
        locallyLikedOnly = upstreamLimited;
      });
      if (upstreamLimited) {
        defaultToast(
          context,
          context.l10n.tr(
            '已在本机点赞，当前服务端暂不支持同步',
            en: 'Liked locally; the server does not support syncing yet',
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrient("$error\n$stackTrace");
      if (!mounted) return;
      setState(() {
        likeLoading = false;
      });
      defaultToast(
        context,
        context.l10n.tr("点赞失败：$error", en: "Failed to like comment: $error"),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contentFontSize = (theme.textTheme.bodyMedium?.fontSize ?? 14) -
        .5 +
        currentFontSizeAdjust(
          FontSizeAdjustType.fontSizeAdjustCommentContent,
        );

    final comment = widget.comment;
    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final levelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
    );
    final datetimeStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: .78),
    );
    var content = comment.content
        .replaceAll(
          "<div style='flex-direction:row;flex-wrap:wrap;'>",
          "",
        )
        .replaceAll("</div>", "");
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(comment.photo, size: 32),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        comment.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(comment.addtime, style: datetimeStyle),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Lv.${comment.expinfo.level}',
                        style: levelStyle,
                      ),
                    ),
                    const Spacer(),
                    if (comment.replys.isNotEmpty) ...[
                      _CommentMetaPill(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: '${comment.replys.length}',
                        accent: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                    ],
                    GestureDetector(
                      onTap: _likeComment,
                      child: _CommentMetaPill(
                        icon: liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: '${comment.likes + (locallyLikedOnly ? 1 : 0)}',
                        loading: likeLoading,
                        accent: liked ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onLongPress: () {
                    confirmCopy(
                      context,
                      comment.content
                          .replaceAll(
                            "<div style='flex-direction:row;flex-wrap:wrap;'>",
                            "",
                          )
                          .replaceAll("</div>", ""),
                    );
                  },
                  child: Text.rich(
                    TextSpan(
                      children: content.length < 200
                          ? [...parseCommentBody(content)]
                          : [
                              ...parseCommentBody(content.substring(0, 200)),
                              TextSpan(text: "..."),
                              TextSpan(
                                text:
                                    context.l10n.tr("  全文", en: "  Full text"),
                                style: TextStyle(
                                  color: theme.colorScheme.secondary
                                      .withOpacity(.5),
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => TextPreviewScreen(
                                          text: content,
                                        ),
                                      ),
                                    );
                                  },
                              ),
                            ],
                    ),
                    style: TextStyle(
                      fontSize: contentFontSize,
                      height: 1.42,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                ...widget.gotoComic
                    ? [
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            if (comment.AID != null) {
                              Navigator.push(context, MaterialPageRoute(
                                  builder: (BuildContext context) {
                                return ComicInfoScreen(comment.AID!, null);
                              }));
                            }
                          },
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.menu_book_rounded,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      comment.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ]
                    : [],
              ],
            ),
          ),
        ],
      ),
    );
  }

  //<img style="width:18px;height:18px" src="https://www.cdnxxx-proxy.xyz/media/emoji/0002.png" alt="doge" />
  List<InlineSpan> parseCommentBody(String comment) {
    var regex = RegExp(
        r'<img style=\"width:18px;height:18px\" src=\"(.*?)\" alt=\"(.*?)\" />');
    var matches = regex.allMatches(comment);
    if (matches.isNotEmpty) {
      var list = comment.split(regex);
      var spans = <InlineSpan>[];
      for (var i = 0; i < list.length; i++) {
        spans.add(TextSpan(text: list[i]));
        if (i < list.length - 1) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image.network(
              matches.elementAt(i).group(1)!,
              width: 18,
              height: 18,
              fit: BoxFit.cover,
            ),
          ));
        }
      }
      return spans;
    }
    return [TextSpan(text: comment)];
  }
}

class _CommentMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool loading;

  const _CommentMetaPill({
    required this.icon,
    required this.label,
    required this.accent,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: accent,
              ),
            )
          else
            Icon(icon, size: 12, color: accent),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _CommentChildrenScreen extends StatefulWidget {
  final String? mode;
  final int aid;
  final Comment comment;

  const _CommentChildrenScreen({
    required this.mode,
    required this.aid,
    required this.comment,
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CommentChildrenScreenState();
}

class _CommentChildrenScreenState extends State<_CommentChildrenScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.tr('评论回复', en: 'Replies')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _ComicCommentItem(
              mode: widget.mode,
              aid: widget.aid,
              comment: widget.comment,
              gotoComic: false,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                ...widget.comment.replys.map((e) => _buildComment(
                      context,
                      e,
                      false,
                      widget.mode,
                      false,
                    )),
                _buildPostComment(
                  context,
                  widget.comment.CID,
                  widget.aid,
                  () {
                    // setState(() {
                    //   _future = _loadPage();
                    // });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
