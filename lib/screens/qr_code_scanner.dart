import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

class QRCodeScanner extends StatefulWidget {
  const QRCodeScanner({super.key});

  @override
  State<QRCodeScanner> createState() => _QRCodeScannerState();
}

class _QRCodeScannerState extends State<QRCodeScanner> {
  String scannedURL = "";
  Timer? vibrationTimer;

  @override
  void initState() {
    super.initState();
    vibrationTimer = Timer(const Duration(seconds: 10), () async {
      // If no QR code detected in 10 seconds, vibrate
      if (scannedURL.isEmpty) {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(duration: 200); // short vibration (200ms)
        }
      }
    });
  }

  @override
  void dispose() {
    vibrationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'QR Code Scanner',
          style: TextStyle(color: theme.colorScheme.onBackground),
        ),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: Column(
        children: [
          // Camera scanner view
          Expanded(
            child: MobileScanner(
              onDetect: (BarcodeCapture capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  setState(() {
                    scannedURL = barcode.rawValue ?? "No URL found";
                  });
                  vibrationTimer?.cancel(); // stop vibration timer once scanned
                }
              },
            ),
          ),

          const SizedBox(height: 20),

          // Display scanned URL
          Text(
            scannedURL.isEmpty
                ? "No URL scanned yet."
                : "Scanned URL: $scannedURL",
            style: const TextStyle(color: Colors.red),
          ),

          const SizedBox(height: 30),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Confirm button
              GestureDetector(
                onTap: () {
                  if (scannedURL.trim().isNotEmpty &&
                      Uri.tryParse(scannedURL)?.hasAbsolutePath == true) {
                    launchUrl(Uri.parse(scannedURL));
                  }
                },
                child: const CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.green,
                  child: Icon(Icons.check, color: Colors.white),
                ),
              ),
              const SizedBox(width: 20),

              // Re-scan button
              GestureDetector(
                onTap: () {
                  setState(() {
                    scannedURL = "";
                  });
                  // restart vibration timer
                  vibrationTimer = Timer(const Duration(seconds: 10), () async {
                    if (scannedURL.isEmpty) {
                      final hasVibrator = await Vibration.hasVibrator();
                      if (hasVibrator == true) {
                        Vibration.vibrate(duration: 200);
                      }
                    }
                  });
                },
                child: const CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.red,
                  child: Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
