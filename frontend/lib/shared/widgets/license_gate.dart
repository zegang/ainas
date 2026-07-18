import 'package:flutter/material.dart';
import '../../services/lic_service.dart';

/// Wraps [child] so it is only visible when the current license grants
/// permission for [feature].  When locked, shows an optional [lockedWidget]
/// (default: a disabled-look placeholder).
class LicenseGate extends StatefulWidget {
  final String feature;
  final Widget child;
  final Widget Function(BuildContext)? lockedBuilder;

  const LicenseGate({
    super.key,
    required this.feature,
    required this.child,
    this.lockedBuilder,
  });

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  final _lic = LicService();
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _check();
    _lic.addListener(_onLicChanged);
  }

  @override
  void dispose() {
    _lic.removeListener(_onLicChanged);
    super.dispose();
  }

  void _onLicChanged() {
    _check();
  }

  Future<void> _check() async {
    final g = await _lic.hasFeature(widget.feature);
    if (mounted) setState(() => _granted = g);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) return const SizedBox.shrink();
    if (_granted == true) return widget.child;

    if (widget.lockedBuilder != null) return widget.lockedBuilder!(context);
    return _defaultLocked();
  }

  Widget _defaultLocked() {
    return AbsorbPointer(
      absorbing: true,
      child: Opacity(
        opacity: 0.35,
        child: widget.child,
      ),
    );
  }
}

/// Conditionally shows an action behind a feature permission.  When the
/// feature is not licensed, [onTap] is ignored and the tile shows a lock
/// icon instead.
class LicenseListTile extends StatefulWidget {
  final String feature;
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final bool showLockIcon;

  const LicenseListTile({
    super.key,
    required this.feature,
    required this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showLockIcon = true,
  });

  @override
  State<LicenseListTile> createState() => _LicenseListTileState();
}

class _LicenseListTileState extends State<LicenseListTile> {
  final _lic = LicService();
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _check();
    _lic.addListener(_onLicChanged);
  }

  @override
  void dispose() {
    _lic.removeListener(_onLicChanged);
    super.dispose();
  }

  void _onLicChanged() {
    _check();
  }

  Future<void> _check() async {
    final g = await _lic.hasFeature(widget.feature);
    if (mounted) setState(() => _granted = g);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      onTap: (_granted == true) ? widget.onTap : null,
      trailing: (_granted == false && widget.showLockIcon)
          ? const Icon(Icons.lock_outline, color: Colors.grey)
          : null,
    );
  }
}
