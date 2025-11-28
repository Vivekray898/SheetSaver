import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PageSelectorScreen extends StatefulWidget {
  final dynamic inputFile; // File or Uint8List
  final int pageCount;

  const PageSelectorScreen({
    super.key,
    required this.inputFile,
    required this.pageCount,
  });

  @override
  State<PageSelectorScreen> createState() => _PageSelectorScreenState();
}

class _PageSelectorScreenState extends State<PageSelectorScreen> {
  late List<int> _selectedPages;
  Uint8List? _pdfBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedPages = List.generate(widget.pageCount, (i) => i);
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    try {
      if (widget.inputFile is Uint8List) {
        _pdfBytes = widget.inputFile;
      } else if (widget.inputFile is File) {
        _pdfBytes = await (widget.inputFile as File).readAsBytes();
      } else if (widget.inputFile is String) {
        _pdfBytes = await File(widget.inputFile).readAsBytes();
      }
    } catch (e) {
      debugPrint("Error loading bytes: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _togglePage(int index) {
    setState(() {
      if (_selectedPages.contains(index)) {
        _selectedPages.remove(index);
      } else {
        _selectedPages.add(index);
        _selectedPages.sort(); // Maintain original order for now
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPages = List.generate(widget.pageCount, (i) => i);
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedPages = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Pages"),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: const Text("All", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: _deselectAll,
            child: const Text("None", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: widget.pageCount,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedPages.contains(index);
                      return GestureDetector(
                        onTap: () => _togglePage(index),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: isSelected
                                    ? Border.all(color: Colors.green, width: 3)
                                    : Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: PdfPageThumbnail(
                                  pdfBytes: _pdfBytes!,
                                  pageIndex: index,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Positioned(
                                top: 8,
                                right: 8,
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.green,
                                  child: Icon(Icons.check,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            Positioned(
                              bottom: 8,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  "Page ${index + 1}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "${_selectedPages.length} pages selected\n→ ${(_selectedPages.length / 2).ceil()} sheets",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      FilledButton(
                        onPressed: _selectedPages.isEmpty
                            ? null
                            : () {
                                Navigator.pop(context, _selectedPages);
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                        ),
                        child: const Text("Continue"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class PdfPageThumbnail extends StatefulWidget {
  final Uint8List pdfBytes;
  final int pageIndex;

  const PdfPageThumbnail({
    super.key,
    required this.pdfBytes,
    required this.pageIndex,
  });

  @override
  State<PdfPageThumbnail> createState() => _PdfPageThumbnailState();
}

class _PdfPageThumbnailState extends State<PdfPageThumbnail> {
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _renderPage();
  }

  Future<void> _renderPage() async {
    try {
      await for (final page in Printing.raster(
        widget.pdfBytes,
        pages: [widget.pageIndex],
        dpi: 72,
      )) {
        final pngBytes = await page.toPng();
        if (mounted) {
          setState(() {
            _imageBytes = pngBytes;
          });
        }
        break; // Only first frame needed
      }
    } catch (e) {
      debugPrint("Error rendering thumbnail: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageBytes == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Image.memory(
      _imageBytes!,
      fit: BoxFit.contain,
    );
  }
}
