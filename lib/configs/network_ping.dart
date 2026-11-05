import 'dart:async';
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

class HostLatencyProbe {
  final String host;
  final int milliseconds;

  const HostLatencyProbe({
    required this.host,
    required this.milliseconds,
  });
}

Future<HostLatencyProbe?> selectFastestHost(
  Iterable<String> hosts,
  Future<int> Function(String host) ping, {
  Duration timeout = const Duration(milliseconds: 1800),
  bool returnOnFirstSuccess = false,
}) async {
  final candidates = <String>[];
  final seen = <String>{};
  for (final host in hosts) {
    final normalized = host.trim();
    if (normalized.isNotEmpty && seen.add(normalized.toLowerCase())) {
      candidates.add(normalized);
    }
  }
  if (candidates.isEmpty) return null;

  if (returnOnFirstSuccess) {
    final completer = Completer<HostLatencyProbe?>();
    var pending = candidates.length;
    for (final host in candidates) {
      unawaited(() async {
        HostLatencyProbe? result;
        try {
          final milliseconds = await ping(host).timeout(timeout);
          if (milliseconds > 0) {
            result = HostLatencyProbe(
              host: host,
              milliseconds: milliseconds,
            );
          }
        } catch (_) {
          // Another route may still answer before the timeout.
        }
        if (result != null && !completer.isCompleted) {
          completer.complete(result);
          return;
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }());
    }
    return completer.future;
  }

  final results = await Future.wait(candidates.map((host) async {
    try {
      final milliseconds = await ping(host).timeout(timeout);
      if (milliseconds <= 0) return null;
      return HostLatencyProbe(host: host, milliseconds: milliseconds);
    } catch (_) {
      return null;
    }
  }));
  final available = results.whereType<HostLatencyProbe>().toList();
  if (available.isEmpty) return null;
  available.sort((left, right) {
    final latency = left.milliseconds.compareTo(right.milliseconds);
    if (latency != 0) return latency;
    return left.host.toLowerCase().compareTo(right.host.toLowerCase());
  });
  return available.first;
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
