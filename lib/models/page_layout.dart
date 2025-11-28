import 'dart:ui';

import 'combine_mode.dart';

enum PagePosition { left, right, top, bottom, full }

class PageLayout {
  final int pageIndex; // Original page number from source PDF
  final int sheetIndex; // Which combined sheet this appears on (0, 1, 2...)
  final PagePosition
      position; // Slot within the sheet (left/right/top/bottom/full)
  double scale; // Scale factor (0.5 to 2.0)
  Offset offset; // X,Y offset for repositioning
  double rotation; // Rotation angle (0, 90, 180, 270)
  bool isEdited; // Track if user manually edited this page

  PageLayout({
    required this.pageIndex,
    required this.sheetIndex,
    required this.position,
    this.scale = 1.0,
    this.offset = Offset.zero,
    this.rotation = 0.0,
    this.isEdited = false,
  });

  PageLayout copyWith({
    int? pageIndex,
    int? sheetIndex,
    PagePosition? position,
    double? scale,
    Offset? offset,
    double? rotation,
    bool? isEdited,
  }) {
    return PageLayout(
      pageIndex: pageIndex ?? this.pageIndex,
      sheetIndex: sheetIndex ?? this.sheetIndex,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      offset: offset ?? this.offset,
      rotation: rotation ?? this.rotation,
      isEdited: isEdited ?? this.isEdited,
    );
  }
}

class CombinedSheet {
  final int sheetIndex;
  final List<PageLayout> pages; // Usually 2 pages (left + right)

  CombinedSheet({
    required this.sheetIndex,
    required this.pages,
  });
}

class DocumentLayout {
  final List<CombinedSheet> sheets;
  final int totalSourcePages;
  final CombineMode layoutMode;

  DocumentLayout({
    required this.sheets,
    required this.totalSourcePages,
    required this.layoutMode,
  });

  // Method to recalculate layout when a page is edited
  void recalculateLayout(int editedPageIndex) {
    final editedPage =
        getAllPages().firstWhere((p) => p.pageIndex == editedPageIndex);

    // If page scale changed significantly, may need to reflow
    if (editedPage.scale < 0.7 || editedPage.scale > 1.5) {
      _reflowFromPage(editedPageIndex);
    }

    // If page was rotated, check if it affects neighbor
    if (editedPage.rotation != 0) {
      _adjustNeighborPage(editedPageIndex);
    }
  }

  void _reflowFromPage(int startPageIndex) {
    // Logic to reflow pages if one becomes too small/large
    // Example: If page becomes very small, try to fit 3 pages per sheet
    // Or if page becomes very large, give it full sheet
    // Placeholder for advanced logic
  }

  void _adjustNeighborPage(int pageIndex) {
    // Find the page on the same sheet
    final editedPage =
        getAllPages().firstWhere((p) => p.pageIndex == pageIndex);

    if (editedPage.sheetIndex >= sheets.length) return;

    final sameSheetPages = sheets[editedPage.sheetIndex].pages;

    // If there's a neighbor page, adjust its position slightly
    for (var page in sameSheetPages) {
      if (page.pageIndex != pageIndex && !page.isEdited) {
        // Auto-adjust neighbor to maintain balance
        // Example: If left page rotated, shift right page slightly
        // Placeholder for advanced logic
      }
    }
  }

  // Method to get all pages as flat list
  List<PageLayout> getAllPages() {
    return sheets.expand((sheet) => sheet.pages).toList();
  }
}
