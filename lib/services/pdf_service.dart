import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
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

  Future<Uint8List> combinePdfWithLayout(
    dynamic inputFile,
    DocumentLayout layout,
  ) async {
    final bytes = await _resolveBytes(inputFile);

    final pdf = pw.Document();
    // Landscape mode: A4 landscape (pages side-by-side)
    // Portrait mode: A4 portrait (pages stacked vertically)
    final PdfPageFormat pageFormat = layout.layoutMode == CombineMode.landscape
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4; // Portrait A4: 210mm x 297mm

    // Render each sheet
    for (final sheet in layout.sheets) {
      if (layout.layoutMode == CombineMode.portrait) {
        // Portrait mode: Stack pages vertically using Column with Expanded
        // Source portrait pages are rotated 90° clockwise to become landscape
        // Then stacked vertically on portrait A4
        final List<pw.Widget> columnChildren = [];

        for (int i = 0; i < sheet.pages.length; i++) {
          final pageLayout = sheet.pages[i];
          // Render and rotate page 90° clockwise (portrait → landscape)
          final imageBytes = await _renderAndRotatePageForPortraitMode(
              bytes, pageLayout.pageIndex);
          final image = pw.MemoryImage(imageBytes);

          columnChildren.add(
            pw.Expanded(
              flex: 1,
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
          );

          // Add divider between pages (not after the last one)
          if (i < sheet.pages.length - 1) {
            columnChildren.add(pw.SizedBox(height: 4));
            columnChildren.add(pw.Divider(thickness: 1));
            columnChildren.add(pw.SizedBox(height: 4));
          }
        }

        // If only one page, add empty expanded to fill the other half
        if (sheet.pages.length == 1) {
          columnChildren.add(pw.Expanded(flex: 1, child: pw.Container()));
        }

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(12),
            build: (context) {
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: columnChildren,
              );
            },
          ),
        );
      } else {
        // Landscape mode: Use Row with side-by-side layout (no rotation)
        final List<pw.Widget> rowChildren = [];

        for (int i = 0; i < sheet.pages.length; i++) {
          final pageLayout = sheet.pages[i];
          final imageBytes =
              await _renderPageToImage(bytes, pageLayout.pageIndex);
          final image = pw.MemoryImage(imageBytes);

          rowChildren.add(
            pw.Expanded(
              flex: 1,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
          );

          // Add divider between pages (not after the last one)
          if (i < sheet.pages.length - 1) {
            rowChildren.add(
              pw.Container(
                width: 1,
                color: PdfColors.grey400,
              ),
            );
          }
        }

        // If only one page, add empty expanded to fill the other half
        if (sheet.pages.length == 1) {
          rowChildren.add(pw.Expanded(flex: 1, child: pw.Container()));
        }

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(12),
            build: (context) {
              return pw.Row(
                children: rowChildren,
              );
            },
          ),
        );
      }
    }

    return pdf.save();
  }

  /// Render page and rotate 90° clockwise for portrait mode
  /// This converts portrait source pages to landscape orientation
  Future<Uint8List> _renderAndRotatePageForPortraitMode(
      Uint8List pdfBytes, int pageIndex) async {
    // Render page to image
    final originalBytes = await _renderPageToImage(pdfBytes, pageIndex);

    // Decode the image
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      throw Exception('Failed to decode page $pageIndex');
    }

    // Check if page is portrait (height > width) - if so, rotate 90° clockwise
    if (originalImage.height > originalImage.width) {
      // Rotate 90° clockwise to make it landscape
      final rotatedImage = img.copyRotate(originalImage, angle: 90);
      return Uint8List.fromList(img.encodePng(rotatedImage));
    }

    // Already landscape, return as-is
    return originalBytes;
  }

  Future<Uint8List> _renderPageToImage(
      Uint8List pdfBytes, int pageIndex) async {
    // Use printing package to render specific page to image
    await for (final page in Printing.raster(pdfBytes, pages: [pageIndex])) {
      return await page.toPng();
    }
    throw Exception('Failed to render page $pageIndex');
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
