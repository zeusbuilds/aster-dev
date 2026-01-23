import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';
import 'package:aster/features/scan/presentation/widgets/widgets.dart';

/// Scan screen with QR code scanning frame
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final frameSize = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate the position of the frame based on header
          // Frame is inside SafeArea, so calculate relative to safe area content
          final headerHeight =
              spacing.spacing32 +
              spacing.spacing64 +
              spacing.spacing12 +
              spacing.spacing14 +
              spacing.spacing8 +
              spacing.spacing12 +
              spacing.spacing32;
          // Add safe area top to get absolute screen position
          final safeAreaTop = MediaQuery.of(context).padding.top;
          // Small adjustment to align cutout with actual frame position (positive = move down)
          final frameTop = safeAreaTop + headerHeight;
          final frameLeft = (constraints.maxWidth - frameSize) / 2;

          // Create cutout rect for the scan frame
          final cutoutRect = Rect.fromLTWH(
            frameLeft,
            frameTop,
            frameSize,
            frameSize,
          );

          return Stack(
            children: [
              // Background with cutout
              ScanBackground(cutoutRect: cutoutRect),
              // Camera footage will go here later - transparent area in cutout
              Positioned(
                left: frameLeft,
                top: frameTop,
                child: Container(
                  width: frameSize,
                  height: frameSize,
                  color: Colors.transparent,
                  // TODO: Add camera preview here
                ),
              ),
              // UI elements on top
              Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top),
                  const ScanWalletHeader(
                    walletName: 'Wallet 1',
                    walletId: 'HD8H90 PX0S',
                  ),
                  SizedBox(height: spacing.spacing32),
                  const ScanFrame(),
                  const Spacer(),
                  ScanEnterAddressButton(onTap: () {}),
                  SizedBox(
                    height:
                        spacing.bottomSafeHeight +
                        spacing.spacing44 +
                        spacing.spacing24,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
