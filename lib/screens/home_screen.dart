import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/combine_mode.dart';
import '../services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'preview_screen.dart';
import 'preview_editor_screen.dart';
import 'scan_screen.dart';
import 'page_selector_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlatformFile? _selectedFile;
  bool _isProcessing = false;
  final PdfService _pdfService = PdfService();
  CombineMode _selectedMode = CombineMode.landscape;
  int? _pageCount;
  List<int>? _selectedPages;
  bool _isIdCardMode = false;
  bool _autoRotate = true;

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: kIsWeb,
      );

      if (result != null) {
        final file = result.files.first;
        int? pages;
        try {
          final bytes =
              kIsWeb ? file.bytes! : await File(file.path!).readAsBytes();
          final document = syncfusion.PdfDocument(inputBytes: bytes);
          pages = document.pages.count;
          document.dispose();
        } catch (e) {
          debugPrint("Error reading page count: $e");
        }

        if (file.size > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    "Large file detected (>50MB). Processing may take longer."),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }

        setState(() {
          _selectedFile = file;
          _pageCount = pages;
        });
      }
    } catch (e) {
      _showErrorDialog("Failed to pick file: ");
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _pageCount = null;
      _selectedPages = null;
    });
  }

  Future<void> _scanDocuments() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Document scanning is only available on Android and iOS."),
          ),
        );
      }
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScanScreen()),
    );

    if (result != null && result is File) {
      int? pages;
      try {
        final bytes = await result.readAsBytes();
        final document = syncfusion.PdfDocument(inputBytes: bytes);
        pages = document.pages.count;
        document.dispose();
      } catch (e) {
        debugPrint("Error reading page count: $e");
      }

      setState(() {
        _selectedFile = PlatformFile(
          name: "Scanned Document.pdf",
          size: result.lengthSync(),
          path: result.path,
          bytes: null,
        );
        _pageCount = pages;
      });
    }
  }

  Future<void> _processPdf() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      Uint8List? inputBytes;
      if (kIsWeb) {
        inputBytes = _selectedFile!.bytes;
      } else {
        final path = _selectedFile!.path;
        if (path != null) {
          inputBytes = await File(path).readAsBytes();
        }
      }

      if (inputBytes == null) {
        throw Exception("Failed to read file bytes");
      }

      if (_isIdCardMode) {
        final combinedBytes = await _pdfService.createIdCardLayout(inputBytes);

        File? resultFile;
        if (!kIsWeb) {
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/combined_pdf.pdf';
          resultFile = await File(tempPath).writeAsBytes(combinedBytes);
        }

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PreviewScreen(
                pdfBytes: combinedBytes,
                originalFile: resultFile,
              ),
            ),
          );
        }
      } else {
        // Standard mode: Use new Interactive Editor
        final initialLayout = await _pdfService.generateInitialLayout(
          inputBytes,
          mode: _selectedMode,
        );

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PreviewEditorScreen(
                pdfFile: inputBytes,
                initialLayout: initialLayout,
              ),
            ),
          );
        }
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120.0,
            floating: false,
            pinned: true,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                "SheetSaver",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      top: -10,
                      child: Icon(
                        Icons.picture_as_pdf,
                        size: 100,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildMainCard()),
                                const SizedBox(width: 24),
                                Expanded(
                                    child: _buildFeaturesList(vertical: true)),
                              ],
                            )
                          : Column(
                              children: [
                                _buildMainCard(),
                                const SizedBox(height: 32),
                                _buildFeaturesList(),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // _buildHeader removed as it is integrated into SliverAppBar

  Widget _buildMainCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined,
                    size: 48, color: colorScheme.secondary),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: colorScheme.primary),
                const SizedBox(width: 8),
                Icon(Icons.description, size: 48, color: colorScheme.primary),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              "2 Pages → 1 Page",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Save 50% paper • Eco-friendly • Cheaper printing",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_selectedFile != null) _buildSelectedFileCard(),
            const SizedBox(height: 24),
            _buildModeSelector(),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto-rotate portrait pages'),
              subtitle: const Text('Rotate pages to use space efficiently'),
              value: _autoRotate,
              onChanged: (value) {
                setState(() {
                  _autoRotate = value;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            if (_isProcessing)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text("Processing...",
                      style: TextStyle(color: colorScheme.onSurface)),
                ],
              )
            else
              Column(
                children: [
                  if (_selectedFile == null)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text("Upload PDF"),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _scanDocuments,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text("Scan Documents"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_selectedFile != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _processPdf,
                        icon: const Icon(Icons.merge_type),
                        label: const Text("Combine Pages"),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.secondaryContainer),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.picture_as_pdf,
                color: colorScheme.onSecondaryContainer, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedFile!.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _getFileSizeString(_selectedFile!.size),
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                if (_pageCount != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.pages, size: 12, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        "${_selectedPages?.length ?? _pageCount} pages → ${((_selectedPages?.length ?? _pageCount!) / 2).ceil()} sheets",
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        _getEstimatedTime(
                            _selectedPages?.length ?? _pageCount!),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                color: colorScheme.onSurfaceVariant,
                tooltip: "Remove file",
              ),
              IconButton(
                onPressed: _openPageSelector,
                icon: const Icon(Icons.edit_document),
                color: colorScheme.primary,
                tooltip: "Select Pages",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPageSelector() async {
    if (_selectedFile == null || _pageCount == null) return;

    dynamic input;
    if (kIsWeb) {
      input = _selectedFile!.bytes;
    } else {
      input = File(_selectedFile!.path!);
    }

    final List<int>? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PageSelectorScreen(
          inputFile: input,
          pageCount: _pageCount!,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedPages = result;
      });
    }
  }

  String _getFileSizeString(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KB";
    }
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  String _getEstimatedTime(int pages) {
    if (pages <= 10) return "~5 seconds";
    if (pages <= 50) return "~30 seconds";
    return "~1-2 minutes";
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Choose orientation",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildModeTile(
          mode: CombineMode.landscape,
          title: "Book Style (Landscape)",
          subtitle: "Best for notebooks and booklets",
        ),
        _buildModeTile(
          mode: CombineMode.portrait,
          title: "Document Style (Portrait)",
          subtitle: "Stacks pages vertically",
        ),
        _buildModeTile(
          mode: CombineMode.auto,
          title: "Auto Detect",
          subtitle: "We pick the best layout",
        ),
        const Divider(height: 32),
        SwitchListTile(
          value: _isIdCardMode,
          onChanged: (value) {
            setState(() {
              _isIdCardMode = value;
            });
          },
          title: const Text("ID Card Mode"),
          subtitle: const Text("For Aadhaar, PAN, etc. (Requires 2 pages)"),
          secondary: const Icon(Icons.badge, color: Colors.indigo),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildModeTile({
    required CombineMode mode,
    required String title,
    required String subtitle,
  }) {
    return RadioListTile<CombineMode>(
      value: mode,
      groupValue: _selectedMode,
      onChanged: _isIdCardMode
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                _selectedMode = value;
              });
            },
      title: Text(title,
          style: TextStyle(color: _isIdCardMode ? Colors.grey : null)),
      subtitle: Text(subtitle,
          style: TextStyle(color: _isIdCardMode ? Colors.grey : null)),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildFeaturesList({bool vertical = false}) {
    final features = [
      _buildFeatureItem(
        Icons.savings,
        "Save Money",
        "Reduce printing costs",
        Colors.amber,
      ),
      _buildFeatureItem(
        Icons.park,
        "Save Trees",
        "Environment friendly",
        Colors.green,
      ),
      _buildFeatureItem(
        Icons.touch_app,
        "Easy to Use",
        "Just upload & download",
        Colors.blue,
      ),
    ];

    if (vertical) {
      return Column(
        children: [
          ...features.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: e,
              )),
          const SizedBox(height: 16),
          _buildTipsSection(),
        ],
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: features.map((e) => Expanded(child: e)).toList(),
        ),
        const SizedBox(height: 24),
        _buildTipsSection(),
      ],
    );
  }

  Widget _buildTipsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: const ExpansionTile(
        title: Text("💡 Tips for best results"),
        children: [
          ListTile(
            leading: Icon(Icons.scanner, size: 20),
            title: Text("Use high-quality scans"),
            dense: true,
          ),
          ListTile(
            leading: Icon(Icons.rotate_right, size: 20),
            title: Text("Ensure pages are correctly oriented"),
            dense: true,
          ),
          ListTile(
            leading: Icon(Icons.preview, size: 20),
            title: Text("Check preview before downloading"),
            dense: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
      IconData icon, String title, String subtitle, Color color) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style:
                  TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
