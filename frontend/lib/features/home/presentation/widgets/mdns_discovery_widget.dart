import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/mdns_service.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/mdns_server_detail_page.dart';

const Duration _mdnsScanTimeout = Duration(seconds: 20);

class MdnsDiscoveryWidget extends StatefulWidget {
  final String? currentTargetUrl;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenBrowser;

  const MdnsDiscoveryWidget({
    super.key,
    this.currentTargetUrl,
    this.onRefresh,
    this.onOpenBrowser,
  });

  @override
  State<MdnsDiscoveryWidget> createState() => _MdnsDiscoveryWidgetState();
}

class _MdnsDiscoveryWidgetState extends State<MdnsDiscoveryWidget> {
  bool _isScanning = false;
  bool _mdnsTimedOut = false;
  List<NasServer> _discoveredServers = [];
  StreamSubscription<NasServer>? _mdnsSubscription;
  DateTime? _mdnsScanStart;
  Duration _mdnsElapsed = Duration.zero;
  Timer? _mdnsElapsedTimer;

  @override
  void initState() {
    super.initState();
    _startMdnsScan();
  }

  @override
  void dispose() {
    _mdnsSubscription?.cancel();
    _mdnsElapsedTimer?.cancel();
    super.dispose();
  }

  void _startMdnsScan() {
    if (kIsWeb) return;
    _mdnsSubscription?.cancel();
    _mdnsElapsedTimer?.cancel();
    setState(() {
      _isScanning = true;
      _mdnsTimedOut = false;
      _discoveredServers.clear();
      _mdnsScanStart = DateTime.now();
      _mdnsElapsed = Duration.zero;
    });
    _mdnsElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _mdnsElapsed = DateTime.now().difference(_mdnsScanStart!));
    });
    _mdnsSubscription = MdnsService.scanForServers(searchText: 'ainas', timeout: _mdnsScanTimeout).listen(
      (server) {
        if (!mounted) return;
        setState(() {
          _discoveredServers.removeWhere(
            (s) => s.host == server.host && s.port == server.port,
          );
          _discoveredServers.add(server);
        });
      },
      onDone: () {
        _mdnsElapsedTimer?.cancel();
        if (mounted) {
          setState(() {
            _isScanning = false;
            if (_discoveredServers.isEmpty) _mdnsTimedOut = true;
          });
        }
      },
      onError: (_) {
        _mdnsElapsedTimer?.cancel();
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  void _onServiceSelected(NasServer server) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MdnsServerDetailPage(server: server),
      ),
    );
  }

  void _handleRefresh() {
    _startMdnsScan();
    widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (kIsWeb) {
      return Card(
        elevation: 2,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l10n.mdnsWebLimitationTitle, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.mdnsWebLimitationDesc,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.mdnsAvailableServers, style: Theme.of(context).textTheme.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onOpenBrowser != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_full, size: 20),
                        onPressed: widget.onOpenBrowser,
                        tooltip: l10n.mdnsBrowseAll,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    if (_isScanning)
                      Text('${_mdnsElapsed.inSeconds}s',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                    else
                      IconButton(icon: const Icon(Icons.refresh), onPressed: _handleRefresh),
                    if (_isScanning) ...[
                      const SizedBox(width: 6),
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ],
                ),
              ],
            ),
            const Divider(),
            if (_isScanning && _discoveredServers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        '${l10n.mdnsScanningServers} (${_mdnsElapsed.inSeconds}s)',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else if (_discoveredServers.isEmpty && _mdnsTimedOut)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Center(child: Text(l10n.mdnsNoServers, style: TextStyle(color: Colors.grey.shade600))),
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.mdnsScanTimedOut} (${_mdnsElapsed.inSeconds} s)',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _handleRefresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(l10n.mdnsScanAgain),
                    ),
                  ],
                ),
              )
            else if (_discoveredServers.isEmpty && !_isScanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(l10n.mdnsNoServers)),
              )
            else
              Column(
                children: [
                  if (_isScanning)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                            const SizedBox(height: 8),
                            Text(
                              '${l10n.mdnsScanningServers} (${_discoveredServers.length} found, ${_mdnsElapsed.inSeconds}s)',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _discoveredServers.length,
                    itemBuilder: (context, index) {
                      final server = _discoveredServers[index];
                      final isTarget = widget.currentTargetUrl != null && server.url == widget.currentTargetUrl;
                      return ListTile(
                        leading: Icon(
                          isTarget ? Icons.check_circle : Icons.dns_outlined,
                          color: isTarget ? Colors.green : null,
                        ),
                        title: Text(
                          server.name,
                          style: isTarget ? const TextStyle(fontWeight: FontWeight.bold) : null,
                        ),
                        subtitle: Text(
                          server.displayUrl,
                          style: TextStyle(
                            fontSize: 12,
                            color: isTarget ? Colors.green : null,
                          ),
                        ),
                        trailing: Icon(isTarget ? Icons.check_circle : Icons.chevron_right,
                            color: isTarget ? Colors.green : null),
                        tileColor: isTarget ? Colors.green.withOpacity(0.08) : null,
                        shape: isTarget
                            ? RoundedRectangleBorder(
                                side: BorderSide(color: Colors.green.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
                        onTap: () => _onServiceSelected(server),
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
