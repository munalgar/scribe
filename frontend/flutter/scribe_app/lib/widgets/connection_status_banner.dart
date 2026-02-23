import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../services/app_preferences.dart';
import '../services/backend_process.dart';
import '../theme.dart';

/// A banner displayed at the top of the content area when the backend is not
/// connected.  Shows the current status, a retry button, and contextual help
/// depending on whether the backend is managed (built-in) or external.
class ConnectionStatusBanner extends StatefulWidget {
  /// Optional callback invoked when the user taps "Open Settings".
  final VoidCallback? onOpenSettings;

  /// How long to wait after startup before showing the error banner.
  /// This gives the backend time to start up before alarming the user.
  final Duration gracePeriod;

  const ConnectionStatusBanner({
    super.key,
    this.onOpenSettings,
    this.gracePeriod = const Duration(seconds: 5),
  });

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner> {
  /// Whether the startup grace period has elapsed.
  bool _gracePeriodOver = false;
  Timer? _graceTimer;

  @override
  void initState() {
    super.initState();
    _graceTimer = Timer(widget.gracePeriod, () {
      if (mounted) setState(() => _gracePeriodOver = true);
    });
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();

    // Don't show when connected.
    if (conn.state == BackendConnectionState.connected) {
      return const SizedBox.shrink();
    }

    // During the startup grace period, hide the banner so the backend
    // has time to come up without flashing an error at the user.
    if (!_gracePeriodOver) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final prefs = context.watch<AppPreferences>();
    final isManaged = prefs.backendMode == BackendMode.managed;

    final isConnecting = conn.state == BackendConnectionState.connecting;
    final iconData = isConnecting
        ? Icons.sync_rounded
        : Icons.cloud_off_rounded;
    final iconColor = isConnecting ? Colors.orange : theme.colorScheme.error;
    final label = conn.statusMessage;
    final showDevHint =
        !isManaged &&
        AppPreferences.isDevMode &&
        conn.state == BackendConnectionState.error;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(28, 12, 28, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.error.withAlpha(60)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isConnecting) ...[
                if (isManaged)
                  _ManagedRetryButton(onOpenSettings: widget.onOpenSettings)
                else ...[
                  FilledButton.tonalIcon(
                    onPressed: () => conn.retry(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onOpenSettings,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ] else
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                ),
            ],
          ),
          if (conn.reconnectAttempts > 1 && isConnecting) ...[
            const SizedBox(height: 6),
            Text(
              'Auto-reconnecting with backoff…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          // Managed mode: show process status hint
          if (isManaged &&
              !isConnecting &&
              conn.state == BackendConnectionState.error) ...[
            const SizedBox(height: 10),
            _ManagedHint(),
          ],
          // External mode: show dev hint in debug builds
          if (showDevHint) ...[
            const SizedBox(height: 12),
            _DevHint(conn: conn),
          ],
        ],
      ),
    );
  }
}

/// Retry/restart buttons for managed backend mode.
class _ManagedRetryButton extends StatelessWidget {
  final VoidCallback? onOpenSettings;

  const _ManagedRetryButton({this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final process = context.read<BackendProcessManager>();
    final conn = context.read<ConnectionProvider>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          onPressed: () async {
            try {
              final port = await process.restart();
              conn.connect(host: '127.0.0.1', port: port);
            } catch (_) {}
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Restart Server'),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onOpenSettings,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Settings'),
        ),
      ],
    );
  }
}

/// Hint shown in managed mode when the backend process has issues.
class _ManagedHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final process = context.watch<BackendProcessManager>();
    final theme = Theme.of(context);

    final message = switch (process.state) {
      BackendProcessState.stopped =>
        'The built-in server is not running. Tap "Restart Server" above or go to Settings to start it.',
      BackendProcessState.crashed =>
        'The built-in server crashed${process.crashCount > 1 ? ' (${process.crashCount} times)' : ''}. Tap "Restart Server" to try again.',
      BackendProcessState.starting => 'The server is starting up…',
      BackendProcessState.running =>
        'The server is running but the connection was lost. Trying to reconnect…',
    };

    return Row(
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Development-mode helper showing the command to start the backend.
class _DevHint extends StatelessWidget {
  final ConnectionProvider conn;

  const _DevHint({required this.conn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const command = 'bash scripts/dev_backend.sh';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Developer',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Start the backend server:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  command,
                  style: ScribeTheme.monoStyle(
                    context,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy command',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: command));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Or set SCRIBE_BACKEND_HOST / SCRIBE_BACKEND_PORT env vars to connect to a remote server.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
