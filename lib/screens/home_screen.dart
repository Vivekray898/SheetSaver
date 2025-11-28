import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../services/pdf_service.dart';
import '../utils/downloader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlatformFile? _selectedFile;
  bool _isProcessing = false;
  final PdfService _pdfService = PdfService();

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: kIsWeb,
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
        });
      }
    } catch (e) {
      _showErrorDialog("Failed to pick file: $e");
    }
  }

  Future<void> _processPdf() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      dynamic input;
      if (kIsWeb) {
        input = _selectedFile!.bytes;
      } else {
        input = File(_selectedFile!.path!);
      }

      final combinedBytes = await _pdfService.combinePdfPages(input);

      File? resultFile;
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/combined_pdf.pdf';
        resultFile = await File(tempPath).writeAsBytes(combinedBytes);
      }

      if (mounted) {
        _showSuccessDialog(combinedBytes, resultFile);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _downloadPdf(Uint8List bytes, File? file) async {
    try {
      if (kIsWeb) {
        downloadFile(bytes, 'combined_pdf.pdf');
      } else if (file != null) {
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
      _showErrorDialog("Failed to download/share: $e");
    }
  }

  void _showSuccessDialog(Uint8List bytes, File? file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Success!"),
        content: const Text("Your PDF has been combined successfully."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadPdf(bytes, file);
            },
            child: const Text("Download / Share"),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PDF Page Combiner"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf, size: 100, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                "Combine 2 Pages into 1 Sheet",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "Save paper, money, and trees 🌳",
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_selectedFile != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _selectedFile!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (_isProcessing)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Combining pages... This may take a moment"),
                  ],
                )
              else
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text("Upload PDF"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_selectedFile != null)
                      FilledButton.icon(
                        onPressed: _processPdf,
                        icon: const Icon(Icons.merge_type),
                        label: const Text("Combine Pages"),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
