import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Alert-first dashboard in the RuView observatory style: a floating
/// PERIMETER STATUS panel with a giant readout, a LATEST DETECTION panel
/// with technical rows, mesh link health, and the event log.
/// No spectrum charts — this screen answers one question: was something
/// detected? Dark mode only. All signal numbers are estimates
/// (radio-internal units).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final disturbed = state.disturbedLinks;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _alertPanel(disturbed),
            const SizedBox(height: 12),
            _controlRow(),
            const SizedBox(height: 12),
            _radiosCard(),
            const SizedBox(height: 12),
            _latestDetection(),
            const SizedBox(height: 12),
            _linksCompact(disturbed),
            const SizedBox(height: 12),
            _eventsCard(),
            const SizedBox(height: 12),
            const _ScopeNote(),
          ],
        );
      },
    );
  }

  /// The big one: CLEAR (shield) vs DETECTED (warning), observatory style.
  Widget _alertPanel(List<String> disturbed) {
    final detected = state.polling && disturbed.isNotEmpty;
    final idle = !state.polling;
    final color = idle
        ? SentryColors.muted
        : detected
            ? SentryColors.amber
            : SentryColors.green;
    final icon = idle
        ? Icons.pause_circle_outline
        : detected
            ? Icons.warning_amber_rounded
            : Icons.shield_outlined;
    final title = idle ? 'PAUSED' : detected ? 'DETECTED' : 'CLEAR';
    final subtitle = idle
        ? 'PRESS START TO BEGIN MONITORING'
        : detected
            ? '${disturbed.length} LINK DIRECTION(S) DISTURBED'
            : state.history.isEmpty
                ? 'WAITING FOR LINK DATA'
                : 'MONITORING ${state.history.length} LINK DIRECTION(S)';
    final live = !state.settings.simulatedMode;
    return SentryPanel(
      glow: idle ? null : color,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PERIMETER STATUS', style: SentryType.section()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: SentryColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: live ? SentryColors.green : SentryColors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      live ? 'LIVE' : 'SIM',
                      style: SentryType.chip(
                        live ? SentryColors.green : SentryColors.orange,
                      ).copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(icon, color: color, size: 52),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: SentryType.readout(40, color)
                      .copyWith(letterSpacing: 5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: SentryType.section(11)),
          if (detected) ...[
            const SizedBox(height: 8),
            Text(
              disturbed.join('  ·  '),
              style: SentryType.rowValue(SentryColors.amber)
                  .copyWith(fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: state.polling ? state.stop : state.start,
              child: Text(state.polling ? 'STOP' : 'START'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlRow() {
    final live = !state.settings.simulatedMode;
    return SentryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SOURCE', style: SentryType.section()),
          const SizedBox(height: 10),
          _dataRow(
            live ? 'RADIO' : 'MODE',
            live ? state.settings.radioIp : 'SIMULATED LINK DATA',
            SentryColors.blue,
          ),
          const SizedBox(height: 6),
          _dataRow('STATUS', state.connectionLabel, SentryColors.muted),
          if (state.error != null) ...[
            const SizedBox(height: 6),
            Text(state.error!,
                style: SentryType.rowValue(SentryColors.red)),
          ],
        ],
      ),
    );
  }

  /// Most recent confirmed crossing, with size estimate and duration.
  /// Per-radio status: which drivers are polling, their link counts,
  /// and any errors. The banner above fires if ANY driver detects.
  Widget _radiosCard() {
    final statuses = state.driverStatuses;
    return SentryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('RADIOS', style: SentryType.section()),
              const Spacer(),
              Text(
                state.settings.simulatedMode
                    ? 'SIMULATED'
                    : '${statuses.length} DRIVER${statuses.length == 1 ? '' : 'S'}',
                style: SentryType.section(10).copyWith(
                    color: SentryColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!state.polling)
            Text('NOT POLLING — PRESS START.',
                style: SentryType.section(10)
                    .copyWith(color: SentryColors.muted))
          else if (statuses.isEmpty)
            Text('NO RADIOS ENABLED — ADD ONE IN SETTINGS.',
                style: SentryType.section(10)
                    .copyWith(color: SentryColors.orange))
          else
            for (final s in statuses)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.error != null
                            ? SentryColors.red
                            : driverColor(s.driverId),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.label,
                        style: SentryType.rowValue(
                                SentryColors.onDark)
                            .copyWith(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      s.error ??
                          '${s.linkCount} LINKS',
                      style: SentryType.section(10).copyWith(
                          color: s.error != null
                              ? SentryColors.red
                              : SentryColors.muted),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _latestDetection() {
    if (state.events.isEmpty) {
      return SentryPanel(
        child: Row(
          children: [
            const Icon(Icons.radar,
                color: SentryColors.muted, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LATEST DETECTION', style: SentryType.section()),
                  const SizedBox(height: 6),
                  Text('NO CROSSINGS DETECTED YET',
                      style: SentryType.rowLabel()),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final e = state.events.first;
    final sizeColor = switch (e.sizeEstimate) {
      'S' => SentryColors.blue,
      'M' => SentryColors.amber,
      _ => SentryColors.red,
    };
    return SentryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('LATEST DETECTION', style: SentryType.section()),
              const Spacer(),
              SentryChip(label: 'SIZE ${e.sizeEstimate}', color: sizeColor),
            ],
          ),
          const SizedBox(height: 12),
          _dataRow('TIME', _fmtTime(e.timestamp), SentryColors.onDark),
          const SizedBox(height: 6),
          _dataRow('LINK', shortLinkKey(e.linkKey), SentryColors.onDark),
          const SizedBox(height: 6),
          _dataRow('DIP',
              '-${e.dipDepth.toStringAsFixed(0)} EST', SentryColors.red),
          const SizedBox(height: 6),
          _dataRow('LASTED', e.durationLabel, SentryColors.onDark),
          const SizedBox(height: 6),
          _dataRow(
              'AI CLASSIFY',
              e.aiLabel == null
                  ? '—'
                  : '${e.aiLabel} ${(e.aiConfidence! * 100).toStringAsFixed(0)}% EST',
              SentryColors.purple),
          const SizedBox(height: 10),
          Text('SIZE AND AI LABELS ARE HEURISTIC ESTIMATES, NOT IDENTIFICATION. '
              'THE CLASSIFIER WAS TRAINED ON SYNTHETIC DATA.',
              style: SentryType.section(9)),
        ],
      ),
    );
  }

  /// Label / value technical row, RuView style.
  Widget _dataRow(String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: SentryType.rowLabel())),
        Expanded(
            child: Text(value, style: SentryType.rowValue(color))),
      ],
    );
  }

  /// One compact row per link direction — health only, no charts.
  Widget _linksCompact(List<String> disturbed) {
    final keys = state.history.keys.toList()..sort();
    return SentryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MESH LINKS', style: SentryType.section()),
          const SizedBox(height: 10),
          if (keys.isEmpty)
            Text('NO LINK DATA YET', style: SentryType.rowLabel()),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: disturbed.contains(k)
                          ? SentryColors.amber
                          : SentryColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(shortLinkKey(k), style: SentryType.rowValue(SentryColors.onDark)),
                  ),
                  Text(
                    'SNR ${state.history[k]!.last.snrLabel}  ·  DIP ${state.history[k]!.last.dipLabel}',
                    style: SentryType.rowLabel().copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _eventsCard() {
    return SentryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CROSSING EVENTS', style: SentryType.section()),
          const SizedBox(height: 10),
          if (state.events.isEmpty)
            Text('NO CROSSINGS DETECTED YET',
                style: SentryType.rowLabel()),
          for (final e in state.events.take(30))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: SentryColors.amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_fmtTime(e.timestamp)} · ${shortLinkKey(e.linkKey)}${e.aiLabel == null ? '' : ' · AI ${e.aiLabel}'}',
                          style: SentryType.rowValue(SentryColors.onDark),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SIZE ${e.sizeEstimate} EST · DIP -${e.dipDepth.toStringAsFixed(0)} EST · LASTED ${e.durationLabel}',
                          style: SentryType.rowLabel().copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _ScopeNote extends StatelessWidget {
  const _ScopeNote();

  @override
  Widget build(BuildContext context) {
    return SentryPanel(
      child: Text(
        'SCOPE — WITH 2 RADIOS THIS IS A SINGLE-LINK TRIPWIRE: CROSSING ALERTS '
        'PLUS A CRUDE SIZE ESTIMATE (S/M/L) FROM THE DIP. TYPE, HEADING, SPEED '
        'AND POSITION NEED 3+ MESH NODES; THOSE READOUTS UNLOCK AS RADIOS JOIN.',
        style: SentryType.section(10).copyWith(height: 1.6),
      ),
    );
  }
}
