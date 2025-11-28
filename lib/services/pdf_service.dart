import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:printing/printing.dart';

class PdfService {
  Future<Uint8List> combinePdfPages(dynamic inputFile) async {
    try {
      Uint8List bytes;
      if (kIsWeb) {
        // On web, inputFile should be PlatformFile or bytes
        // But the prompt specified File inputFile.
        // We'll handle dynamic to support both if we refactor later,
        // but for now we assume the caller handles getting bytes if it's not a File.
        if (inputFile is Uint8List) {
          bytes = inputFile;
        } else {
          // If it's a PlatformFile from file_picker
          try {
            bytes = inputFile.bytes!;
          } catch (e) {
            throw Exception(
                "On web, input must be bytes or PlatformFile with bytes.");
          }
        }
      } else {
        if (inputFile is File) {
          bytes = await inputFile.readAsBytes();
        } else if (inputFile is String) {
          bytes = await File(inputFile).readAsBytes();
        } else {
          throw Exception("Unsupported file type");
        }
      }

      // Read using syncfusion as requested
      final syncfusion.PdfDocument document =
          syncfusion.PdfDocument(inputBytes: bytes);
      final int pageCount = document.pages.count;
      document.dispose();

      if (pageCount == 0) {
        throw Exception("This PDF is empty or corrupted.");
      }

      final pdf = pw.Document();

      for (int i = 0; i < pageCount; i += 2) {
        final image1Bytes = await _renderPageToImage(bytes, i);
        if (image1Bytes == null) continue;
        final image1 = pw.MemoryImage(image1Bytes);

        pw.MemoryImage? image2;
        if (i + 1 < pageCount) {
          final image2Bytes = await _renderPageToImage(bytes, i + 1);
          if (image2Bytes != null) {
            image2 = pw.MemoryImage(image2Bytes);
          }
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            build: (pw.Context context) {
              return pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Image(image1, fit: pw.BoxFit.contain),
                    ),
                  ),
                  if (image2 != null)
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Image(image2, fit: pw.BoxFit.contain),
                      ),
                    )
                  else
                    pw.Expanded(child: pw.Container()),
                ],
              );
            },
          ),
        );
      }

      return await pdf.save();
    } catch (e) {
      throw Exception("Failed to process PDF: $e");
    }
  }

  Future<Uint8List?> _renderPageToImage(Uint8List bytes, int pageIndex) async {
    try {
      await for (final page
          in Printing.raster(bytes, pages: [pageIndex], dpi: 144)) {
        return await page.toPng();
      }
    } catch (e) {
      debugPrint("Error rendering page $pageIndex: $e");
    }
    return null;
  }
}
