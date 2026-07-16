import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ainas_frontend/services/lic_service.dart';
import 'package:ainas_frontend/features/license/license_page.dart' as lic;

class AdSplashScreen extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const AdSplashScreen({super.key, required this.child, this.duration = const Duration(milliseconds: 2200)});

  @override
  State<AdSplashScreen> createState() => _AdSplashScreenState();
}

class _AdSplashScreenState extends State<AdSplashScreen> {
  bool _showChild = false;
  bool _showLicenseCheck = false;

  @override
  void initState() {
    super.initState();
    Timer(widget.duration, () async {
      if (!mounted) return;
      final licensed = await LicService().isLicensed();
      if (!mounted) return;
      if (licensed) {
        setState(() => _showChild = true);
      } else {
        setState(() => _showLicenseCheck = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLicenseCheck) {
      return lic.LicActivationPage(
        onLicensed: () {
          if (mounted) setState(() {
            _showLicenseCheck = false;
            _showChild = true;
          });
        },
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showChild
          ? widget.child
          : Scaffold(
              backgroundColor: Colors.blueGrey.shade900,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 24,
                              color: Colors.black.withOpacity(0.25),
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.campaign, size: 56, color: Colors.blueGrey.shade900),
                            const SizedBox(height: 16),
                            Text(
                              'Sponsored Message',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Discover AI-NAS features while we prepare your workspace.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blueGrey.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
