import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/combine_mode.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'preview_screen.dart';
import 'preview_editor_screen.dart';
import 'scan_screen.dart';
import 'document_scanner_screen.dart';
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
  CombineMode _selectedMode = CombineMode.auto;
  int? _pageCount;
  List<int>? _selectedPages;
  bool _isIdCardMode = false;
  bool _autoRotate = true;
  int _currentNavIndex = 0;

  // Mock recent documents for demo
  final List<Map<String, dynamic>> _recentDocs = [];

  // Responsive breakpoints
  bool get _isTablet => MediaQuery.of(context).size.width >= 600;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 900;

  /// Request storage permissions based on Android version
  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+ (API 33+) - Request granular media permissions
        final photos = await Permission.photos.request();
        // For PDF files, we primarily need photos permission or storage
        if (photos.isGranted) return true;

        // Try manage external storage as fallback
        final manage = await Permission.manageExternalStorage.request();
        return manage.isGranted;
      } else if (sdkInt >= 30) {
        // Android 11-12 (API 30-32)
        final status = await Permission.manageExternalStorage.request();
        if (status.isGranted) return true;

        // Fallback to regular storage
        final storage = await Permission.storage.request();
        return storage.isGranted;
      } else {
        // Android 10 and below
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } else if (Platform.isIOS) {
      // iOS handles permissions automatically via file picker
      return true;
    }
    return true;
  }

  /// Request camera permission for document scanning
  Future<bool> _requestCameraPermission() async {
    if (kIsWeb) return false;

    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<void> _pickFile() async {
    // Request permission first
    final hasPermission = await _requestStoragePermission();

    if (!hasPermission) {
      if (mounted) {
        _showPermissionDeniedDialog('Storage');
      }
      return;
    }

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
              SnackBar(
                content: const Text(
                    "Large file detected. Processing may take longer."),
                backgroundColor: AppColors.warning,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
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
      _showErrorDialog("Failed to pick file");
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
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Scanning is only available on mobile devices.")),
      );
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Document scanning is only available on Android and iOS.")),
        );
      }
      return;
    }

    // Request camera permission for scanning
    final hasCameraPermission = await _requestCameraPermission();
    if (!hasCameraPermission) {
      if (mounted) {
        _showPermissionDeniedDialog('Camera');
      }
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DocumentScannerScreen()),
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

    setState(() => _isProcessing = true);

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
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 8),
            const Text("Error"),
          ],
        ),
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

  void _showPermissionDeniedDialog(String permissionType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(
              "$permissionType Permission Required",
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          "$permissionType permission is required to access files. "
          "Please enable it in Settings.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel",
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text("Open Settings",
                style: TextStyle(color: AppColors.primary)),
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
      setState(() => _selectedPages = result);
    }
  }

  String _getFileSizeString(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _buildBody(),
      ),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    switch (_currentNavIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildFilesTab();
      case 2:
        return _buildToolsTab();
      case 3:
        return _buildMeTab();
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildQuickActionsGrid(),
          const SizedBox(height: 24),
          if (_selectedFile != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSelectedFileCard(),
            ),
            const SizedBox(height: 24),
          ],
          _buildRecentsSection(),
          const SizedBox(height: 100), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildFilesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_outlined, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No files yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanned documents will appear here',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PDF Tools',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          _buildToolItem(Icons.merge, 'Merge PDFs', 'Combine multiple PDFs'),
          _buildToolItem(
              Icons.call_split, 'Split PDF', 'Extract pages from PDF'),
          _buildToolItem(Icons.compress, 'Compress', 'Reduce file size'),
          _buildToolItem(Icons.rotate_right, 'Rotate', 'Rotate PDF pages'),
          _buildToolItem(Icons.text_fields, 'Extract Text', 'OCR to text'),
        ],
      ),
    );
  }

  Widget _buildToolItem(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildMeTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          _buildSettingsCard(),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            Icons.badge_outlined,
            'ID Card Mode',
            trailing: Switch(
              value: _isIdCardMode,
              onChanged: (v) => setState(() => _isIdCardMode = v),
            ),
          ),
          Divider(color: AppColors.border, height: 1),
          _buildSettingsTile(
            Icons.sync_outlined,
            'Auto-rotate',
            trailing: Switch(
              value: _autoRotate,
              onChanged: (v) => setState(() => _autoRotate = v),
            ),
          ),
          Divider(color: AppColors.border, height: 1),
          _buildSettingsTile(
            Icons.format_size,
            'Combine Mode',
            subtitle: _getModeLabel(_selectedMode),
            onTap: _showModeSelector,
          ),
          Divider(color: AppColors.border, height: 1),
          _buildSettingsTile(Icons.info_outline, 'About', onTap: () {}),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title,
      {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: AppColors.textSecondary))
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: AppColors.textTertiary)
              : null),
      onTap: onTap,
    );
  }

  String _getModeLabel(CombineMode mode) {
    switch (mode) {
      case CombineMode.landscape:
        return 'Book Layout';
      case CombineMode.portrait:
        return 'Document Layout';
      case CombineMode.auto:
        return 'Auto';
    }
  }

  void _showModeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Combine Mode',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildModeOption(CombineMode.auto, Icons.auto_awesome, 'Auto',
                'Automatically detect best layout'),
            _buildModeOption(CombineMode.landscape, Icons.menu_book, 'Book',
                'Side-by-side pages for books'),
            _buildModeOption(CombineMode.portrait, Icons.description,
                'Document', 'Vertical layout for documents'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption(
      CombineMode mode, IconData icon, String title, String subtitle) {
    final isSelected = _selectedMode == mode;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: isSelected ? AppColors.primary : AppColors.textSecondary),
      ),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isSelected ? AppColors.primary : AppColors.textPrimary)),
      subtitle:
          Text(subtitle, style: TextStyle(color: AppColors.textSecondary)),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.primary)
          : null,
      onTap: () {
        setState(() => _selectedMode = mode);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.document_scanner,
                color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SheetSaver Pro',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Scan & Combine PDFs',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.search, color: AppColors.textSecondary, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon:
                Icon(Icons.more_vert, color: AppColors.textSecondary, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    final actions = [
      {
        'icon': Icons.document_scanner,
        'label': 'Smart Scan',
        'color': AppColors.smartScanBg,
        'action': _scanDocuments
      },
      {
        'icon': Icons.picture_as_pdf,
        'label': 'PDF Tools',
        'color': AppColors.pdfToolsBg,
        'action': () => setState(() => _currentNavIndex = 2)
      },
      {
        'icon': Icons.photo_library,
        'label': 'Import',
        'color': AppColors.importImagesBg,
        'action': _pickFile
      },
      {
        'icon': Icons.insert_drive_file,
        'label': 'Files',
        'color': AppColors.importFilesBg,
        'action': () => setState(() => _currentNavIndex = 1)
      },
      {
        'icon': Icons.badge,
        'label': 'ID Card',
        'color': AppColors.idCardsBg,
        'action': () {
          setState(() => _isIdCardMode = true);
          _pickFile();
        }
      },
      {
        'icon': Icons.text_fields,
        'label': 'Extract Text',
        'color': AppColors.extractTextBg,
        'action': () {}
      },
      {
        'icon': Icons.auto_fix_high,
        'label': 'AI Tools',
        'color': AppColors.solverAiBg,
        'action': () {}
      },
      {
        'icon': Icons.apps,
        'label': 'All Features',
        'color': AppColors.allFeaturesBg,
        'action': () {}
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          return _buildQuickActionItem(
            icon: action['icon'] as IconData,
            label: action['label'] as String,
            color: action['color'] as Color,
            onTap: action['action'] as VoidCallback,
          );
        },
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentNavIndex = 1),
                child: Text(
                  'See all',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _recentDocs.isEmpty
              ? _buildEmptyRecents()
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentDocs.length,
                  itemBuilder: (context, index) =>
                      _buildRecentDocCard(_recentDocs[index]),
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyRecents() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'No recent documents',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the scan button to get started',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDocCard(Map<String, dynamic> doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.picture_as_pdf, color: AppColors.error),
        ),
        title: Text(
          doc['name'] ?? 'Document',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          doc['date'] ?? 'Just now',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Icon(Icons.more_vert, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppShadows.fab,
      ),
      child: FloatingActionButton(
        onPressed: _isProcessing ? null : _scanDocuments,
        backgroundColor: AppColors.primary,
        elevation: 0,
        child: _isProcessing
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(Icons.camera_alt, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_outlined, Icons.home_filled, 'Home', 0),
              _buildNavItem(Icons.folder_outlined, Icons.folder, 'Files', 1),
              const SizedBox(width: 60), // Space for FAB
              _buildNavItem(Icons.build_outlined, Icons.build, 'Tools', 2),
              _buildNavItem(Icons.person_outline, Icons.person, 'Me', 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      IconData icon, IconData activeIcon, String label, int index) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                color: isActive ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedFile!.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_getFileSizeString(_selectedFile!.size)}${_pageCount != null ? ' • $_pageCount pages' : ''}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _openPageSelector,
                icon: Icon(Icons.edit_outlined, size: 20),
                color: AppColors.primary,
              ),
              IconButton(
                onPressed: _clearSelection,
                icon: Icon(Icons.close, size: 20),
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _processPdf,
              icon: _isProcessing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Icon(Icons.merge_type, size: 20),
              label: Text(
                _isProcessing ? 'Processing...' : 'Combine Pages',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.success.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
