import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

class HostPingResult {
  final int coldMilliseconds;
  final int bestMilliseconds;
  final int samples;

  const HostPingResult({
    required this.coldMilliseconds,
    required this.bestMilliseconds,
    required this.samples,
  });
}

/// The first request creates DNS/TCP/TLS state; the second measures the route
/// after that cold-start cost has been paid.
Future<HostPingResult> measureHostPing(
  Future<int> Function() request,
) async {
  final cold = await request();
  if (cold <= 0) {
    throw StateError('invalid ping result');
  }
  var best = cold;
  var samples = 1;
  try {
    final warm = await request();
    if (warm > 0) {
      best = math.min(best, warm);
      samples++;
    }
  } catch (_) {
    // Keep the successful cold sample when the warm-up retry fails.
  }
  return HostPingResult(
    coldMilliseconds: cold,
    bestMilliseconds: best,
    samples: samples,
  );
}

String formatPingDuration(int milliseconds) {
  if (milliseconds < 1000) {
    return '$milliseconds ms';
  }
  final seconds = milliseconds / 1000;
  return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
}

class NetworkPingStatus extends StatelessWidget {
  final HostPingResult? result;
  final bool loading;
  final bool failed;

  const NetworkPingStatus.loading({Key? key})
      : result = null,
        loading = true,
        failed = false,
        super(key: key);

  const NetworkPingStatus.failed({Key? key})
      : result = null,
        loading = false,
        failed = true,
        super(key: key);

  const NetworkPingStatus.result(this.result, {Key? key})
      : loading = false,
        failed = false,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 5),
          Text(context.l10n.tr('测速中', en: 'Testing')),
        ],
      );
    }
    if (failed || result == null) {
      return _status(
        context,
        context.l10n.tr('失败', en: 'Failed'),
        Colors.red,
      );
    }

    final ping = result!;
    final color = ping.bestMilliseconds <= 200
        ? Colors.green
        : ping.bestMilliseconds <= 500
            ? Colors.amber
            : Colors.orange;
    return Tooltip(
      message: context.l10n.tr(
        '首次 ${formatPingDuration(ping.coldMilliseconds)}，'
        '热连接最快 ${formatPingDuration(ping.bestMilliseconds)}，'
        '共 ${ping.samples} 次',
        en: 'First ${formatPingDuration(ping.coldMilliseconds)}, '
            'best warm ${formatPingDuration(ping.bestMilliseconds)}, '
            '${ping.samples} sample(s)',
      ),
      child: _status(
        context,
        'HTTP ${formatPingDuration(ping.bestMilliseconds)}',
        color,
      ),
    );
  }

  Widget _status(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('•', style: TextStyle(color: color)),
        Text(' $label'),
      ],
    );
  }
}
