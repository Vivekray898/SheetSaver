import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import '../models/page_layout.dart';
import '../models/combine_mode.dart';

class PdfService {
  Future<Uint8List> combinePdfPages(
    dynamic inputFile, {
    CombineMode mode = CombineMode.landscape,
    List<int>? selectedPages,
    bool autoRotate = true,
  }) async {
    try {
      final bytes = await _resolveBytes(inputFile);
      final document = syncfusion.PdfDocument(inputBytes: bytes);

      try {
        final pageCount = document.pages.count;
        if (pageCount == 0) {
          throw Exception("This PDF is empty or corrupted.");
        }

        final CombineMode effectiveMode =
            _resolveCombineMode(mode, document, pageCount);
        final List<int> pagesToProcess =
            _resolvePages(pageCount, selectedPages);

        final output = syncfusion.PdfDocument();
        output.pageSettings.size = syncfusion.PdfPageSize.a4;
        output.pageSettings.orientation = effectiveMode == CombineMode.landscape
            ? syncfusion.PdfPageOrientation.landscape
            : syncfusion.PdfPageOrientation.portrait;

        for (int i = 0; i < pagesToProcess.length; i += 2) {
          final int firstIndex = pagesToProcess[i];
          final syncfusion.PdfPage newPage = output.pages.add();
          final slots = _resolveSlots(newPage.getClientSize(), effectiveMode);

          _drawPageTemplate(
            sourcePage: document.pages[firstIndex],
            targetGraphics: newPage.graphics,
            slot: slots.first,
            canRotate: autoRotate && effectiveMode == CombineMode.landscape,
          );

          if (i + 1 < pagesToProcess.length) {
            final int secondIndex = pagesToProcess[i + 1];
            _drawPageTemplate(
              sourcePage: document.pages[secondIndex],
              targetGraphics: newPage.graphics,
              slot: slots[1],
              canRotate: autoRotate && effectiveMode == CombineMode.landscape,
            );
          }

          if (pagesToProcess.length > 4) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final Uint8List outputBytes = Uint8List.fromList(await output.save());
        output.dispose();

        return outputBytes;
      } finally {
        document.dispose();
      }
    } catch (e) {
      throw Exception("Failed to process PDF: $e");
    }
  }

  CombineMode _resolveCombineMode(
    CombineMode requested,
    syncfusion.PdfDocument document,
    int pageCount,
  ) {
    if (requested != CombineMode.auto || pageCount == 0) {
      return requested;
    }
    final firstPageSize = document.pages[0].size;
    return firstPageSize.width >= firstPageSize.height
        ? CombineMode.landscape
        : CombineMode.portrait;
  }

  List<int> _resolvePages(int pageCount, List<int>? selectedPages) {
    final pages = selectedPages == null
        ? List<int>.generate(pageCount, (index) => index)
        : List<int>.from(selectedPages);

    if (pages.isEmpty) {
      throw Exception("Please select at least one page to combine.");
    }

    final hasInvalidIndex = pages.any((page) => page < 0 || page >= pageCount);
    if (hasInvalidIndex) {
      throw Exception("Selected pages exceed the document length.");
    }

    return pages;
  }

  List<Rect> _resolveSlots(Size pageSize, CombineMode mode) {
    const double padding = 24;
    if (mode == CombineMode.landscape) {
      final double slotWidth = (pageSize.width - padding * 3) / 2;
      final double slotHeight = pageSize.height - padding * 2;
      return [
        Rect.fromLTWH(padding, padding, slotWidth, slotHeight),
        Rect.fromLTWH(padding * 2 + slotWidth, padding, slotWidth, slotHeight),
      ];
    }

    final double slotHeight = (pageSize.height - padding * 3) / 2;
    final double slotWidth = pageSize.width - padding * 2;
    return [
      Rect.fromLTWH(padding, padding, slotWidth, slotHeight),
      Rect.fromLTWH(padding, padding * 2 + slotHeight, slotWidth, slotHeight),
    ];
  }

  void _drawPageTemplate({
    required syncfusion.PdfPage sourcePage,
    required syncfusion.PdfGraphics targetGraphics,
    required Rect slot,
    required bool canRotate,
  }) {
    final template = sourcePage.createTemplate();
    final Size original = template.size;
    final bool shouldRotate = canRotate && original.height > original.width;

    final double contentWidth = shouldRotate ? original.height : original.width;
    final double contentHeight =
        shouldRotate ? original.width : original.height;

    final double scale = math.min(
      slot.width / contentWidth,
      slot.height / contentHeight,
    );

    if (!scale.isFinite || scale <= 0) {
      return;
    }

    final double drawWidth = contentWidth * scale;
    final double drawHeight = contentHeight * scale;
    final double offsetX = slot.left + (slot.width - drawWidth) / 2;
    final double offsetY = slot.top + (slot.height - drawHeight) / 2;

    targetGraphics.save();
    if (shouldRotate) {
      targetGraphics.translateTransform(
        offsetX + drawWidth / 2,
        offsetY + drawHeight / 2,
      );
      targetGraphics.rotateTransform(-90);
      targetGraphics.drawPdfTemplate(
        template,
        Offset(-drawWidth / 2, -drawHeight / 2),
        Size(drawWidth, drawHeight),
      );
    } else {
      targetGraphics.drawPdfTemplate(
        template,
        Offset(offsetX, offsetY),
        Size(drawWidth, drawHeight),
      );
    }
    targetGraphics.restore();
  }

  Future<Uint8List> createIdCardLayout(dynamic inputFile) async {
    try {
      final bytes = await _resolveBytes(inputFile);
      final document = syncfusion.PdfDocument(inputBytes: bytes);

      try {
        final pageCount = document.pages.count;
        if (pageCount != 2) {
          throw Exception(
              "ID Card mode requires exactly 2 pages (Front & Back). Found $pageCount pages.");
        }

        final output = syncfusion.PdfDocument();
        output.pageSettings.size = syncfusion.PdfPageSize.a4;
        final page = output.pages.add();
        final Size canvas = page.getClientSize();
        const double padding = 28;
        final double slotHeight = (canvas.height - padding * 3) / 2;
        final double slotWidth = canvas.width - padding * 2;

        final Rect topSlot = Rect.fromLTWH(
          padding,
          padding,
          slotWidth,
          slotHeight,
        );
        final Rect bottomSlot = Rect.fromLTWH(
          padding,
          padding * 2 + slotHeight,
          slotWidth,
          slotHeight,
        );

        _drawPageTemplate(
          sourcePage: document.pages[0],
          targetGraphics: page.graphics,
          slot: topSlot,
          canRotate: false,
        );
        _drawPageTemplate(
          sourcePage: document.pages[1],
          targetGraphics: page.graphics,
          slot: bottomSlot,
          canRotate: false,
        );

        final double dividerY = padding + slotHeight + padding / 2;
        final dividerPen = syncfusion.PdfPen(
          syncfusion.PdfColor(140, 140, 140),
          dashStyle: syncfusion.PdfDashStyle.dash,
        );
        page.graphics.drawLine(
          dividerPen,
          Offset(padding, dividerY),
          Offset(canvas.width - padding, dividerY),
        );

        final scissorFont = syncfusion.PdfStandardFont(
          syncfusion.PdfFontFamily.helvetica,
          14,
        );
        page.graphics.drawString(
          '✂',
          scissorFont,
          brush: syncfusion.PdfSolidBrush(syncfusion.PdfColor(80, 80, 80)),
          bounds: Rect.fromLTWH(
            canvas.width / 2 - 8,
            dividerY - 10,
            16,
            20,
          ),
        );

        final Uint8List result = Uint8List.fromList(await output.save());
        output.dispose();
        return result;
      } finally {
        document.dispose();
      }
    } catch (e) {
      throw Exception("Failed to create ID Card layout: $e");
    }
  }

  Future<Uint8List> _resolveBytes(dynamic inputFile) async {
    if (kIsWeb) {
      if (inputFile is Uint8List) {
        return inputFile;
      }
      if (inputFile?.bytes is Uint8List) {
        return inputFile.bytes as Uint8List;
      }
      throw Exception(
          "On web, input must be bytes or a PlatformFile that exposes bytes.");
    }

    if (inputFile is Uint8List) {
      return inputFile;
    }
    if (inputFile is File) {
      return inputFile.readAsBytes();
    }
    if (inputFile is String) {
      return File(inputFile).readAsBytes();
    }

    throw Exception("Unsupported file type");
  }

  // NEW METHODS FOR PREVIEW EDITOR

  Future<DocumentLayout> generateInitialLayout(
    dynamic inputFile, {
    CombineMode mode = CombineMode.landscape,
  }) async {
    final bytes = await _resolveBytes(inputFile);
    final syncfusion.PdfDocument originalDoc =
        syncfusion.PdfDocument(inputBytes: bytes);

    try {
      final int totalPages = originalDoc.pages.count;
      final CombineMode resolvedMode = _resolveCombineMode(
        mode,
        originalDoc,
        totalPages,
      );
      final CombineMode effectiveMode = resolvedMode == CombineMode.auto
          ? CombineMode.landscape
          : resolvedMode;

      final List<CombinedSheet> sheets = [];
      // Landscape mode: pages side-by-side (left/right) on landscape sheet
      // Portrait mode: pages stacked vertically (top/bottom) on portrait sheet
      // NO rotation in either mode - pages keep their original orientation
      final PagePosition primaryPosition =
          effectiveMode == CombineMode.landscape
              ? PagePosition.left
              : PagePosition.top;
      final PagePosition secondaryPosition =
          effectiveMode == CombineMode.landscape
              ? PagePosition.right
              : PagePosition.bottom;

      for (int i = 0; i < totalPages; i += 2) {
        final firstPage = PageLayout(
          pageIndex: i,
          sheetIndex: sheets.length,
          position: primaryPosition,
          scale: 1.0,
          offset: Offset.zero,
          rotation: 0.0, // No rotation - pages stay in original orientation
        );

        PageLayout? secondPage;
        if (i + 1 < totalPages) {
          secondPage = PageLayout(
            pageIndex: i + 1,
            sheetIndex: sheets.length,
            position: secondaryPosition,
            scale: 1.0,
            offset: Offset.zero,
            rotation: 0.0, // No rotation - pages stay in original orientation
          );
        }

        sheets.add(
          CombinedSheet(
            sheetIndex: sheets.length,
            pages: [
              firstPage,
              if (secondPage != null) secondPage,
            ],
          ),
        );
      }

      return DocumentLayout(
        sheets: sheets,
        totalSourcePages: totalPages,
        layoutMode: effectiveMode,
      );
    } finally {
      originalDoc.dispose();
    }
  }

  /// Combines PDF pages using vector-based approach (fast & high quality)
  /// Portrait mode: Rotates portrait pages 90° and stacks vertically on portrait A4
  /// Landscape mode: Places pages side-by-side on landscape A4
  Future<Uint8List> combinePdfWithLayout(
    dynamic inputFile,
    DocumentLayout layout, {
    void Function(int current, int total)? onProgress,
  }) async {
    debugPrint('=== STARTING PDF COMBINE (Vector Mode) ===');
    final startTime = DateTime.now();

    final bytes = await _resolveBytes(inputFile);
    final sourceDoc = syncfusion.PdfDocument(inputBytes: bytes);

    try {
      final outputDoc = syncfusion.PdfDocument();

      // Set page orientation based on layout mode
      outputDoc.pageSettings.size = syncfusion.PdfPageSize.a4;
      outputDoc.pageSettings.orientation =
          layout.layoutMode == CombineMode.landscape
              ? syncfusion.PdfPageOrientation.landscape
              : syncfusion.PdfPageOrientation.portrait;

      final int totalSheets = layout.sheets.length;

      for (int sheetIdx = 0; sheetIdx < totalSheets; sheetIdx++) {
        final sheet = layout.sheets[sheetIdx];
        debugPrint('Processing sheet ${sheetIdx + 1}/${totalSheets}...');

        // Report progress
        onProgress?.call(sheetIdx + 1, totalSheets);

        // Create new output page
        final outputPage = outputDoc.pages.add();
        final graphics = outputPage.graphics;
        final pageSize = outputPage.getClientSize();

        if (layout.layoutMode == CombineMode.portrait) {
          // Portrait mode: Stack pages vertically, rotate portrait pages 90°
          _drawPortraitLayoutSheet(
            sourceDoc: sourceDoc,
            graphics: graphics,
            pageSize: pageSize,
            pages: sheet.pages,
          );
        } else {
          // Landscape mode: Place pages side-by-side
          _drawLandscapeLayoutSheet(
            sourceDoc: sourceDoc,
            graphics: graphics,
            pageSize: pageSize,
            pages: sheet.pages,
          );
        }

        // Yield to UI thread periodically
        if (sheetIdx % 2 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      // NO COMPRESSION for scanned PDFs - preserves image quality
      outputDoc.compressionLevel = syncfusion.PdfCompressionLevel.none;

      final outputBytes = Uint8List.fromList(outputDoc.saveSync());

      final duration = DateTime.now().difference(startTime);
      debugPrint('=== COMPLETED IN ${duration.inMilliseconds}ms ===');

      outputDoc.dispose();
      return outputBytes;
    } finally {
      sourceDoc.dispose();
    }
  }

  /// Draw pages stacked vertically for portrait layout
  /// Rotates portrait source pages 90° clockwise to appear landscape
  void _drawPortraitLayoutSheet({
    required syncfusion.PdfDocument sourceDoc,
    required syncfusion.PdfGraphics graphics,
    required Size pageSize,
    required List<PageLayout> pages,
  }) {
    // MINIMAL margins for maximum space usage (5pt = ~1.76mm)
    const double padding = 5.0;
    const double dividerHeight = 4.0;

    final double availableHeight = pageSize.height -
        (padding * 2) -
        (pages.length > 1 ? dividerHeight : 0);
    final double slotHeight =
        pages.length > 1 ? availableHeight / 2 : availableHeight;
    final double slotWidth = pageSize.width - (padding * 2);

    for (int i = 0; i < pages.length; i++) {
      final pageLayout = pages[i];
      final sourcePage = sourceDoc.pages[pageLayout.pageIndex];
      final template = sourcePage.createTemplate();
      final sourceSize = sourcePage.size;

      // Check if source is portrait (needs rotation)
      final bool isSourcePortrait = sourceSize.height > sourceSize.width;

      // Calculate slot position
      final double slotY = padding + (i * (slotHeight + dividerHeight));
      final Rect slot = Rect.fromLTWH(padding, slotY, slotWidth, slotHeight);

      if (isSourcePortrait) {
        // Rotate 90° clockwise: portrait → landscape
        _drawRotatedTemplate(
          graphics: graphics,
          template: template,
          sourceSize: sourceSize,
          slot: slot,
          rotationDegrees: 90,
        );
      } else {
        // Already landscape, draw directly
        _drawFittedTemplate(
          graphics: graphics,
          template: template,
          sourceSize: sourceSize,
          slot: slot,
        );
      }
    }

    // Draw thin divider line between pages
    if (pages.length > 1) {
      final dividerY = padding + slotHeight + (dividerHeight / 2);
      graphics.drawLine(
        syncfusion.PdfPen(syncfusion.PdfColor(220, 220, 220), width: 0.5),
        Offset(padding, dividerY),
        Offset(pageSize.width - padding, dividerY),
      );
    }
  }

  /// Draw pages side-by-side for landscape layout
  void _drawLandscapeLayoutSheet({
    required syncfusion.PdfDocument sourceDoc,
    required syncfusion.PdfGraphics graphics,
    required Size pageSize,
    required List<PageLayout> pages,
  }) {
    // MINIMAL margins for maximum space usage (5pt = ~1.76mm)
    const double padding = 5.0;
    const double dividerWidth = 4.0;

    final double availableWidth =
        pageSize.width - (padding * 2) - (pages.length > 1 ? dividerWidth : 0);
    final double slotWidth =
        pages.length > 1 ? availableWidth / 2 : availableWidth;
    final double slotHeight = pageSize.height - (padding * 2);

    for (int i = 0; i < pages.length; i++) {
      final pageLayout = pages[i];
      final sourcePage = sourceDoc.pages[pageLayout.pageIndex];
      final template = sourcePage.createTemplate();
      final sourceSize = sourcePage.size;

      // Calculate slot position
      final double slotX = padding + (i * (slotWidth + dividerWidth));
      final Rect slot = Rect.fromLTWH(slotX, padding, slotWidth, slotHeight);

      // Check if rotation needed (landscape pages on portrait slots or vice versa)
      final bool isSourcePortrait = sourceSize.height > sourceSize.width;
      final bool isSlotPortrait = slotHeight > slotWidth;

      if (isSourcePortrait != isSlotPortrait) {
        // Rotate 90° to fit
        _drawRotatedTemplate(
          graphics: graphics,
          template: template,
          sourceSize: sourceSize,
          slot: slot,
          rotationDegrees: -90,
        );
      } else {
        // Draw directly
        _drawFittedTemplate(
          graphics: graphics,
          template: template,
          sourceSize: sourceSize,
          slot: slot,
        );
      }
    }

    // Draw thin divider line between pages
    if (pages.length > 1) {
      final dividerX = padding + slotWidth + (dividerWidth / 2);
      graphics.drawLine(
        syncfusion.PdfPen(syncfusion.PdfColor(220, 220, 220), width: 0.5),
        Offset(dividerX, padding),
        Offset(dividerX, pageSize.height - padding),
      );
    }
  }

  /// Draw template fitted to slot without rotation
  void _drawFittedTemplate({
    required syncfusion.PdfGraphics graphics,
    required syncfusion.PdfTemplate template,
    required Size sourceSize,
    required Rect slot,
  }) {
    // Use 98% of available space for maximum content size
    final double scale = math.min(
          slot.width / sourceSize.width,
          slot.height / sourceSize.height,
        ) *
        0.98;

    final double drawWidth = sourceSize.width * scale;
    final double drawHeight = sourceSize.height * scale;
    final double offsetX = slot.left + (slot.width - drawWidth) / 2;
    final double offsetY = slot.top + (slot.height - drawHeight) / 2;

    graphics.drawPdfTemplate(
      template,
      Offset(offsetX, offsetY),
      Size(drawWidth, drawHeight),
    );
  }

  /// Draw template with rotation (for portrait→landscape conversion)
  void _drawRotatedTemplate({
    required syncfusion.PdfGraphics graphics,
    required syncfusion.PdfTemplate template,
    required Size sourceSize,
    required Rect slot,
    required double rotationDegrees,
  }) {
    // After rotation: width↔height swap
    final double rotatedWidth = sourceSize.height;
    final double rotatedHeight = sourceSize.width;

    // Use 98% of available space for maximum content size
    final double scale = math.min(
          slot.width / rotatedWidth,
          slot.height / rotatedHeight,
        ) *
        0.98;

    final double centerX = slot.left + slot.width / 2;
    final double centerY = slot.top + slot.height / 2;

    graphics.save();
    graphics.translateTransform(centerX, centerY);
    graphics.rotateTransform(rotationDegrees);

    // Draw centered at origin (rotation pivot)
    graphics.drawPdfTemplate(
      template,
      Offset(-sourceSize.width * scale / 2, -sourceSize.height * scale / 2),
      Size(sourceSize.width * scale, sourceSize.height * scale),
    );

    graphics.restore();
  }
}

class CombinePdfArgs {
  final Uint8List bytes;
  final CombineMode mode;
  final List<int>? selectedPages;
  final bool autoRotate;

  const CombinePdfArgs({
    required this.bytes,
    required this.mode,
    this.selectedPages,
    required this.autoRotate,
  });
}

Future<Uint8List> combinePdfInIsolate(CombinePdfArgs args) {
  final service = PdfService();
  return service.combinePdfPages(
    args.bytes,
    mode: args.mode,
    selectedPages: args.selectedPages,
    autoRotate: args.autoRotate,
  );
}
