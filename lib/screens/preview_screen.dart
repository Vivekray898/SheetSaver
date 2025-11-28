import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/downloader.dart';

class PreviewScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final File?
      originalFile; // Kept for reference if needed, though we use bytes for preview

  const PreviewScreen({
    super.key,
    required this.pdfBytes,
    this.originalFile,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
  }

  void _handleZoomChanged(PdfZoomDetails details) {
    setState(() {
      _zoomLevel = details.newZoomLevel;
    });
  }

  void _zoomIn() {
    _pdfViewerController.zoomLevel = _zoomLevel + 0.25;
  }

  void _zoomOut() {
    if (_zoomLevel > 1.0) {
      _pdfViewerController.zoomLevel = _zoomLevel - 0.25;
    }
  }

  Future<void> _downloadPdf() async {
    try {
      if (kIsWeb) {
        downloadFile(widget.pdfBytes, 'combined_pdf.pdf');
      } else {
        // Mobile download/share logic
        // We need to write the bytes to a file first for sharing
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/combined_pdf.pdf';
        final file = await File(tempPath).writeAsBytes(widget.pdfBytes);

        if (Platform.isAndroid) {
          var status = await Permission.storage.status;
          if (!status.isGranted) {
            status = await Permission.storage.request();
          }

          Directory? downloadsDir;
          try {
            downloadsDir = Directory('/storage/emulated/0/Download');
            if (!await downloadsDir.exists()) {
              downloadsDir = await getExternalStorageDirectory();
            }
          } catch (e) {
            downloadsDir = await getExternalStorageDirectory();
          }

          if (downloadsDir != null) {
            final newPath =
                '${downloadsDir.path}/combined_${DateTime.now().millisecondsSinceEpoch}.pdf';
            await file.copy(newPath);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Saved to $newPath')),
              );
            }
          }
        }

        await Share.shareXFiles([XFile(file.path)], text: 'Combined PDF');
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Error"),
            content: Text("Failed to download/share: $e"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Preview PDF"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                "Zoom: ${(_zoomLevel * 100).round()}%",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SfPdfViewer.memory(
                  widget.pdfBytes,
                  controller: _pdfViewerController,
                  onZoomLevelChanged: _handleZoomChanged,
                  pageLayoutMode: PdfPageLayoutMode.single,
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: "zoom_in",
                        mini: true,
                        onPressed: _zoomIn,
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton(
                        heroTag: "zoom_out",
                        mini: true,
                        onPressed: _zoomOut,
                        child: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text("Go Back & Try Again"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _downloadPdf,
                      icon: const Icon(Icons.download),
                      label: const Text("Looks Good! Download"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
