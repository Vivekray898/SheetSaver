import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/page_layout.dart';
import '../services/pdf_service.dart';

class PreviewEditorScreen extends StatefulWidget {
  final dynamic pdfFile;
  final DocumentLayout initialLayout;

  const PreviewEditorScreen({
    super.key,
    required this.pdfFile,
    required this.initialLayout,
  });

  @override
  State<PreviewEditorScreen> createState() => _PreviewEditorScreenState();
}

class _PreviewEditorScreenState extends State<PreviewEditorScreen> {
  late DocumentLayout _currentLayout;
  int? _selectedPageIndex;
  bool _isProcessing = false;
  List<Uint8List> _previewImages = [];

  @override
  void initState() {
    super.initState();
    _currentLayout = widget.initialLayout;
    _generatePreviews();
  }

  Future<void> _generatePreviews() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      // Generate preview images for each sheet
      _previewImages = await _renderAllSheets();
    } catch (e) {
      debugPrint('Error generating previews: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating preview: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<List<Uint8List>> _renderAllSheets() async {
    final pdfService = PdfService();
    // Generate the PDF with current layout
    final pdfBytes = await pdfService.combinePdfWithLayout(
      widget.pdfFile,
      _currentLayout,
    );

    // Rasterize pages to images
    final images = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes)) {
      images.add(await page.toPng());
    }
    return images;
  }

  void _onPageTap(int pageIndex) {
    setState(() {
      _selectedPageIndex = pageIndex;
    });
  }

  void _updatePageLayout(PageLayout updatedLayout) {
    setState(() {
      // Update the layout in _currentLayout
      final allPages = _currentLayout.getAllPages();
      final index =
          allPages.indexWhere((p) => p.pageIndex == updatedLayout.pageIndex);

      if (index != -1) {
        // Find which sheet this page belongs to
        final sheetIndex = updatedLayout.sheetIndex;
        if (sheetIndex < _currentLayout.sheets.length) {
          final sheet = _currentLayout.sheets[sheetIndex];
          final pageIndexInSheet = sheet.pages
              .indexWhere((p) => p.pageIndex == updatedLayout.pageIndex);

          if (pageIndexInSheet != -1) {
            sheet.pages[pageIndexInSheet] =
                updatedLayout.copyWith(isEdited: true);
          }
        }

        // Recalculate surrounding pages
        _currentLayout.recalculateLayout(updatedLayout.pageIndex);

        // Regenerate preview
        _generatePreviews();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Layout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetAllToDefault,
            tooltip: 'Reset All',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadPdf,
            tooltip: 'Download',
          ),
        ],
      ),
      body: _isProcessing && _previewImages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // LEFT: Preview area (scrollable grid of sheets)
                Expanded(
                  flex: 3,
                  child: _buildPreviewGrid(),
                ),

                // RIGHT: Edit panel (only shown when page selected)
                if (_selectedPageIndex != null)
                  Container(
                    width: 300,
                    decoration: BoxDecoration(
                      border:
                          Border(left: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: _buildEditPanel(),
                  ),
              ],
            ),
    );
  }

  Widget _buildPreviewGrid() {
    // Always landscape A4 sheet with pages side-by-side
    const double a4LandscapeRatio = 1.414; // width / height for A4 landscape

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width > 800 ? 2 : 1,
        childAspectRatio: a4LandscapeRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _currentLayout.sheets.length,
      itemBuilder: (context, sheetIndex) {
        return _buildSheetPreview(sheetIndex);
      },
    );
  }

  Widget _buildSheetPreview(int sheetIndex) {
    final sheet = _currentLayout.sheets[sheetIndex];

    return GestureDetector(
      onTap: () {
        // Show sheet options or zoom in
      },
      child: Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background: Show preview image
            Positioned.fill(
              child: _previewImages.length > sheetIndex
                  ? Image.memory(
                      _previewImages[sheetIndex],
                      fit: BoxFit.contain,
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),

            // Overlay: Clickable areas for each page
            ...sheet.pages.map((pageLayout) {
              return _buildPageOverlay(pageLayout);
            }),

            // Sheet number
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Sheet ${sheetIndex + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageOverlay(PageLayout pageLayout) {
    final isSelected = _selectedPageIndex == pageLayout.pageIndex;
    Alignment alignment = Alignment.center;
    double widthFactor = 1;
    double heightFactor = 1;

    switch (pageLayout.position) {
      case PagePosition.left:
        alignment = Alignment.centerLeft;
        widthFactor = 0.5;
        break;
      case PagePosition.right:
        alignment = Alignment.centerRight;
        widthFactor = 0.5;
        break;
      case PagePosition.top:
        alignment = Alignment.topCenter;
        heightFactor = 0.5;
        break;
      case PagePosition.bottom:
        alignment = Alignment.bottomCenter;
        heightFactor = 0.5;
        break;
      case PagePosition.full:
        alignment = Alignment.center;
        break;
    }

    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: alignment,
        widthFactor: widthFactor,
        heightFactor: heightFactor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onPageTap(pageLayout.pageIndex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.transparent,
                width: 3,
              ),
              color: isSelected
                  ? Colors.blue.withOpacity(0.08)
                  : Colors.transparent,
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: pageLayout.isEdited
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.edit, color: Colors.orange, size: 20),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditPanel() {
    final selectedPage = _currentLayout.getAllPages().firstWhere(
          (p) => p.pageIndex == _selectedPageIndex,
          orElse: () => _currentLayout.sheets.first.pages.first, // Fallback
        );

    if (_selectedPageIndex == null) return Container();

    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Page ${selectedPage.pageIndex + 1}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() => _selectedPageIndex = null);
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Scale control
            const Text('Scale', style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: selectedPage.scale,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: '${(selectedPage.scale * 100).toInt()}%',
              onChanged: (value) {
                _updatePageLayout(
                  selectedPage.copyWith(scale: value),
                );
              },
            ),
            Text(
              '${(selectedPage.scale * 100).toInt()}%',
              style: const TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 24),

            // Position controls
            const Text('Position',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Up arrow
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: () {
                    _updatePageLayout(
                      selectedPage.copyWith(
                        offset: Offset(
                          selectedPage.offset.dx,
                          selectedPage.offset.dy - 10,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Left arrow
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    _updatePageLayout(
                      selectedPage.copyWith(
                        offset: Offset(
                          selectedPage.offset.dx - 10,
                          selectedPage.offset.dy,
                        ),
                      ),
                    );
                  },
                ),
                // Center button
                IconButton(
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () {
                    _updatePageLayout(
                      selectedPage.copyWith(offset: Offset.zero),
                    );
                  },
                ),
                // Right arrow
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () {
                    _updatePageLayout(
                      selectedPage.copyWith(
                        offset: Offset(
                          selectedPage.offset.dx + 10,
                          selectedPage.offset.dy,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Down arrow
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: () {
                    _updatePageLayout(
                      selectedPage.copyWith(
                        offset: Offset(
                          selectedPage.offset.dx,
                          selectedPage.offset.dy + 10,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Rotation control
            const Text('Rotation',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [0, 90, 180, 270].map((angle) {
                return ChoiceChip(
                  label: Text('$angle°'),
                  selected: selectedPage.rotation == angle.toDouble(),
                  onSelected: (selected) {
                    if (selected) {
                      _updatePageLayout(
                        selectedPage.copyWith(rotation: angle.toDouble()),
                      );
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Reset button
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reset This Page'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () {
                _updatePageLayout(
                  PageLayout(
                    pageIndex: selectedPage.pageIndex,
                    sheetIndex: selectedPage.sheetIndex,
                    position: selectedPage.position,
                    scale: 1.0,
                    offset: Offset.zero,
                    rotation: 0.0,
                    isEdited: false,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tips:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Adjust scale to fit content\n'
                    '• Use arrows to fine-tune position\n'
                    '• Rotate for better alignment\n'
                    '• Changes affect this page only',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetAllToDefault() {
    setState(() {
      _currentLayout = widget.initialLayout;
      _selectedPageIndex = null;
      _generatePreviews();
    });
  }

  Future<void> _downloadPdf() async {
    setState(() => _isProcessing = true);

    try {
      final pdfService = PdfService();
      final pdfBytes = await pdfService.combinePdfWithLayout(
        widget.pdfFile,
        _currentLayout,
      );

      if (!mounted) return;

      // Save and share/download
      await Printing.sharePdf(bytes: pdfBytes, filename: 'combined_layout.pdf');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF ready for download!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
