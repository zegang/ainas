import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/mdns_service.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';
import 'package:ainas_frontend/shared/utils/backend_process_manager.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/mdns_server_detail_page.dart';

class MdnsBrowserPage extends StatefulWidget {
  const MdnsBrowserPage({super.key});

  @override
  State<MdnsBrowserPage> createState() => _MdnsBrowserPageState();
}

class _MdnsBrowserPageState extends State<MdnsBrowserPage> {
  final ApiService _api = ApiService();
  bool _isScanning = false;
  final List<NasServer> _servers = [];
  StreamSubscription<NasServer>? _subscription;
  String? _selectedServiceType;
  DateTime? _scanStartTime;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  Set<String> get _serviceTypes =>
      _servers.map((s) => s.serviceType).where((t) => t.isNotEmpty).toSet();

  List<NasServer> get _filteredServers {
    if (_selectedServiceType == null) return _servers;
    return _servers.where((s) => s.serviceType == _selectedServiceType).toList();
  }

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _startScan() {
    if (kIsWeb) return;
    setState(() {
      _isScanning = true;
      _scanStartTime = DateTime.now();
      _elapsed = Duration.zero;
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_scanStartTime!));
    });
    _subscription?.cancel();
    _servers.clear();

    // Check for a running local backend process and add it as a discovered server
    BackendProcessManager.listPids().then((pids) {
      if (pids.isNotEmpty && mounted) {
        final uri = Uri.tryParse(_api.baseUrl);
        final host = uri?.host ?? '127.0.0.1';
        final port = uri?.port ?? 9026;
        setState(() {
          _servers.insert(0, NasServer(
            name: 'Local',
            host: host,
            addresses: [host, '127.0.0.1'],
            port: port,
            priority: 0,
            weight: 0,
            txtRecords: [],
            serviceType: '_http._tcp.local',
          ));
        });
      }
    });

    _subscription = MdnsService.scanForAllServices().listen((server) {
      if (!mounted) return;
      setState(() {
        _servers.removeWhere(
          (s) => s.host == server.host && s.port == server.port,
        );
        _servers.add(server);
      });
    }, onDone: () {
      _elapsedTimer?.cancel();
      if (mounted) setState(() => _isScanning = false);
    }, onError: (_) {
      _elapsedTimer?.cancel();
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _onServiceSelected(NasServer server) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MdnsServerDetailPage(server: server)),
    );
  }

  Future<List<String>> _getLocalAddresses() async {
    if (kIsWeb) return [];
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      final ips = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
      final sorted = ips.toList()..sort();
      sorted.insert(0, '127.0.0.1');
      return sorted;
    } catch (_) {
      return ['127.0.0.1'];
    }
  }

  Future<void> _showAddManualDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final localIps = await _getLocalAddresses();
    final nameCtl = TextEditingController();
    final hostCtl = TextEditingController(text: localIps.first);
    final portCtl = TextEditingController(text: '9026');
    final typeCtl = TextEditingController(text: '_http._tcp.local');
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.mdnsAddServiceTitle),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtl,
                    decoration: InputDecoration(
                      labelText: l10n.mdnsNameLabel,
                      hintText: l10n.mdnsNameHint,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? l10n.mdnsAddServiceRequired : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: hostCtl,
                    decoration: InputDecoration(
                      labelText: l10n.mdnsHostIpLabel,
                      hintText: l10n.mdnsHostIpHint,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? l10n.mdnsAddServiceRequired : null,
                  ),
                  if (localIps.length > 1) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: localIps.map((ip) => ActionChip(
                        label: Text(ip, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                        onPressed: () => hostCtl.text = ip,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: portCtl,
                    decoration: InputDecoration(labelText: l10n.mdnsPortLabel),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return l10n.mdnsAddServiceRequired;
                      final p = int.tryParse(v.trim());
                      if (p == null || p < 1 || p > 65535) return l10n.mdnsInvalidPort;
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: typeCtl,
                    decoration: InputDecoration(
                      labelText: l10n.mdnsServiceTypeLabel,
                      hintText: l10n.mdnsServiceTypeHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                setState(() {
                  _servers.insert(0, NasServer(
                    name: nameCtl.text.trim(),
                    host: hostCtl.text.trim(),
                    port: int.parse(portCtl.text.trim()),
                    addresses: [hostCtl.text.trim(), '127.0.0.1'],
                    serviceType: typeCtl.text.trim(),
                  ));
                });
                Navigator.pop(ctx);
              },
              child: Text(l10n.mdnsAddButton),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mdnsPageTitle),
        actions: [
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_elapsed.inSeconds}s',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(width: 6),
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _startScan),
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddManualDialog),
        ],
      ),
      body: kIsWeb
          ? Center(child: Text(l10n.mdnsWebUnsupported))
          : _servers.isEmpty && _isScanning
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('${l10n.mdnsPageScanning} (${_elapsed.inSeconds}s)',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : _servers.isEmpty && !_isScanning
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dns_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(l10n.mdnsNoServicesFound,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.mdnsScanAgain),
                          ),
                        ],
                      ),
                    )
                  : Column(
                  children: [
                    if (_serviceTypes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              FilterChip(
                                label: Text(l10n.mdnsFilterAllTypes, style: const TextStyle(fontSize: 12)),
                                selected: _selectedServiceType == null,
                                onSelected: (_) => setState(() => _selectedServiceType = null),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                              ..._serviceTypes.map((type) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text(type, style: const TextStyle(fontSize: 12)),
                                  selected: _selectedServiceType == type,
                                  onSelected: (_) => setState(() => _selectedServiceType = type),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async => _startScan(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredServers.length + (_isScanning ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _filteredServers.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final server = _filteredServers[index];
                            final isTarget = _api.baseUrl == server.url;
                      return ListTile(
                        leading: Icon(
                          isTarget ? Icons.check_circle : Icons.dns_outlined,
                          color: isTarget ? Colors.green : null,
                        ),
                        title: Text(server.name,
                            style: isTarget ? const TextStyle(fontWeight: FontWeight.bold) : null),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(server.displayUrl,
                                style: TextStyle(fontSize: 12, color: isTarget ? Colors.green : null)),
                            Text(server.serviceType,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
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
                ),
              ),
            ],
          ),
    );
  }
}
