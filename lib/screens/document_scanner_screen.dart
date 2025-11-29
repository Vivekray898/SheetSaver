import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme/app_theme.dart';

class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _isProcessing = false;
  bool _flashOn = false;
  bool _autoCapture = false;

  // Scanned pages
  List<ScannedPage> _scannedPages = [];
  int _currentPreviewIndex = -1;

  // Animation controllers
  late AnimationController _captureAnimController;
  late Animation<double> _captureAnimation;

  // Scan mode
  ScanMode _scanMode = ScanMode.document;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initializeCamera();

    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  void _initAnimations() {
    _captureAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _captureAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _captureAnimController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        _showError('No cameras available');
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      _showError('Error initializing camera: $e');
    }
  }

  Future<void> _captureImage() async {
    if (!_isCameraInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);

    // Play capture animation
    await _captureAnimController.forward();
    await _captureAnimController.reverse();

    try {
      // Capture image
      final XFile image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      // Save original
      final tempDir = await getTemporaryDirectory();
      final originalPath =
          '${tempDir.path}/scan_orig_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(originalPath).writeAsBytes(bytes);

      // Create scanned page entry
      final scannedPage = ScannedPage(
        originalPath: originalPath,
        enhancedPath: originalPath, // Will be updated after enhancement
        timestamp: DateTime.now(),
      );

      setState(() {
        _scannedPages.add(scannedPage);
        _currentPreviewIndex = _scannedPages.length - 1;
      });

      // Show quick preview with options
      _showCapturePreview(scannedPage);
    } catch (e) {
      _showError('Error capturing image: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _showCapturePreview(ScannedPage page) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CapturePreviewSheet(
        page: page,
        pageNumber: _scannedPages.length,
        onRetake: () {
          Navigator.pop(context);
          setState(() {
            _scannedPages.removeLast();
            _currentPreviewIndex = -1;
          });
        },
        onContinue: () {
          Navigator.pop(context);
          setState(() => _currentPreviewIndex = -1);
        },
        onDone: () {
          Navigator.pop(context);
          _finishScanning();
        },
        onEnhance: () {
          Navigator.pop(context);
          _showEnhanceOptions(page);
        },
      ),
    );
  }

  void _showEnhanceOptions(ScannedPage page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageEnhanceScreen(
          page: page,
          onSave: (enhancedPath) {
            setState(() {
              final index = _scannedPages.indexOf(page);
              if (index != -1) {
                _scannedPages[index] =
                    page.copyWith(enhancedPath: enhancedPath);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _importFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage();

      if (images.isEmpty) return;

      setState(() => _isProcessing = true);

      for (final image in images) {
        final bytes = await image.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/import_${DateTime.now().millisecondsSinceEpoch}_${images.indexOf(image)}.jpg';
        await File(path).writeAsBytes(bytes);

        setState(() {
          _scannedPages.add(ScannedPage(
            originalPath: path,
            enhancedPath: path,
            timestamp: DateTime.now(),
          ));
        });
      }
    } catch (e) {
      _showError('Error importing images: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleFlash() async {
    if (!_isCameraInitialized) return;

    setState(() => _flashOn = !_flashOn);

    try {
      await _cameraController!.setFlashMode(
        _flashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      debugPrint('Flash error: $e');
    }
  }

  Future<void> _finishScanning() async {
    if (_scannedPages.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Create PDF from scanned pages
      final pdf = pw.Document();

      for (final page in _scannedPages) {
        final bytes = await File(page.enhancedPath).readAsBytes();
        final image = pw.MemoryImage(bytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      }

      final output = await getTemporaryDirectory();
      final file = File(
        '${output.path}/scanned_doc_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        Navigator.pop(context, file);
      }
    } catch (e) {
      _showError('Error creating PDF: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showScannedPages() {
    if (_scannedPages.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannedPagesScreen(
          pages: _scannedPages,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final page = _scannedPages.removeAt(oldIndex);
              _scannedPages.insert(newIndex, page);
            });
          },
          onDelete: (index) {
            setState(() {
              _scannedPages.removeAt(index);
            });
          },
          onEnhance: (page) => _showEnhanceOptions(page),
          onFinish: () {
            Navigator.pop(context);
            _finishScanning();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _captureAnimation,
                builder: (context, child) => Transform.scale(
                  scale: _captureAnimation.value,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Viewfinder overlay
          if (_isCameraInitialized) _buildViewfinderOverlay(),

          // Top bar
          _buildTopBar(),

          // Scan mode selector
          _buildScanModeSelector(),

          // Bottom controls
          _buildBottomControls(),

          // Processing overlay
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildViewfinderOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: ViewfinderPainter(
            color: AppColors.primary,
            cornerLength: 40,
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Close button
            _buildIconButton(
              icon: Icons.close,
              onTap: () => Navigator.pop(context),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Scan Document',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Flash toggle
            _buildIconButton(
              icon: _flashOn ? Icons.flash_on : Icons.flash_off,
              onTap: _toggleFlash,
              isActive: _flashOn,
            ),
            // Settings
            _buildIconButton(
              icon: Icons.tune,
              onTap: () {
                // Show settings
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.primary : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildScanModeSelector() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ScanMode.values.map((mode) {
              final isSelected = _scanMode == mode;
              return GestureDetector(
                onTap: () => setState(() => _scanMode = mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          top: 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          children: [
            // Instruction text
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                _scannedPages.isEmpty
                    ? 'Position document within frame'
                    : '${_scannedPages.length} page${_scannedPages.length > 1 ? 's' : ''} scanned',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ),

            // Controls row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery button
                _buildControlButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: _importFromGallery,
                ),

                // Capture button
                GestureDetector(
                  onTap: _captureImage,
                  child: AnimatedBuilder(
                    animation: _captureAnimation,
                    builder: (context, child) => Transform.scale(
                      scale: _captureAnimation.value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color:
                                _isCapturing ? AppColors.primary : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: _isCapturing
                              ? const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),

                // Scanned pages / Done button
                _buildControlButton(
                  icon: _scannedPages.isEmpty
                      ? Icons.auto_awesome_motion_outlined
                      : Icons.check_circle,
                  label: _scannedPages.isEmpty
                      ? 'Batch'
                      : 'Done (${_scannedPages.length})',
                  onTap: _scannedPages.isEmpty
                      ? () => setState(() => _autoCapture = !_autoCapture)
                      : _showScannedPages,
                  isActive: _scannedPages.isNotEmpty,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withOpacity(0.2)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive ? AppColors.primary : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? AppColors.primary : Colors.white,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Processing...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _captureAnimController.dispose();
    super.dispose();
  }
}

// Viewfinder painter
class ViewfinderPainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;

  ViewfinderPainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final margin = 40.0;
    final left = margin;
    final top = size.height * 0.2;
    final right = size.width - margin;
    final bottom = size.height * 0.7;

    // Top-left corner
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), paint);

    // Top-right corner
    canvas.drawLine(
        Offset(right - cornerLength, top), Offset(right, top), paint);
    canvas.drawLine(
        Offset(right, top), Offset(right, top + cornerLength), paint);

    // Bottom-left corner
    canvas.drawLine(
        Offset(left, bottom - cornerLength), Offset(left, bottom), paint);
    canvas.drawLine(
        Offset(left, bottom), Offset(left + cornerLength, bottom), paint);

    // Bottom-right corner
    canvas.drawLine(
        Offset(right - cornerLength, bottom), Offset(right, bottom), paint);
    canvas.drawLine(
        Offset(right, bottom), Offset(right, bottom - cornerLength), paint);

    // Corner dots
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(left, top), 6, dotPaint);
    canvas.drawCircle(Offset(right, top), 6, dotPaint);
    canvas.drawCircle(Offset(left, bottom), 6, dotPaint);
    canvas.drawCircle(Offset(right, bottom), 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Scan modes
enum ScanMode {
  document('Doc'),
  idCard('ID Card'),
  book('Book'),
  whiteboard('Board');

  final String label;
  const ScanMode(this.label);
}

// Scanned page model
class ScannedPage {
  final String originalPath;
  final String enhancedPath;
  final DateTime timestamp;

  ScannedPage({
    required this.originalPath,
    required this.enhancedPath,
    required this.timestamp,
  });

  ScannedPage copyWith({
    String? originalPath,
    String? enhancedPath,
    DateTime? timestamp,
  }) {
    return ScannedPage(
      originalPath: originalPath ?? this.originalPath,
      enhancedPath: enhancedPath ?? this.enhancedPath,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

// Capture preview sheet
class _CapturePreviewSheet extends StatelessWidget {
  final ScannedPage page;
  final int pageNumber;
  final VoidCallback onRetake;
  final VoidCallback onContinue;
  final VoidCallback onDone;
  final VoidCallback onEnhance;

  const _CapturePreviewSheet({
    required this.page,
    required this.pageNumber,
    required this.onRetake,
    required this.onContinue,
    required this.onDone,
    required this.onEnhance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Page $pageNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.tune, color: Colors.white),
                  onPressed: onEnhance,
                ),
              ],
            ),
          ),

          // Preview image
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(page.enhancedPath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRetake,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Retake'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onContinue,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                    label: const Text('Add More'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onDone,
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Image Enhancement Screen
class ImageEnhanceScreen extends StatefulWidget {
  final ScannedPage page;
  final Function(String) onSave;

  const ImageEnhanceScreen({
    super.key,
    required this.page,
    required this.onSave,
  });

  @override
  State<ImageEnhanceScreen> createState() => _ImageEnhanceScreenState();
}

class _ImageEnhanceScreenState extends State<ImageEnhanceScreen> {
  late String _currentPath;
  bool _isProcessing = false;

  // Enhancement settings
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;
  bool _grayscale = false;
  bool _autoEnhance = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.page.enhancedPath;
  }

  Future<void> _applyEnhancements() async {
    setState(() => _isProcessing = true);

    try {
      // Read original image
      final bytes = await File(widget.page.originalPath).readAsBytes();
      var image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Apply brightness and contrast
      if (_brightness != 0 || _contrast != 0) {
        image = img.adjustColor(
          image,
          brightness: 1 + (_brightness / 100),
          contrast: 1 + (_contrast / 100),
          saturation: 1 + (_saturation / 100),
        );
      }

      // Apply grayscale
      if (_grayscale) {
        image = img.grayscale(image);
      }

      // Auto enhance (sharpen + contrast boost)
      if (_autoEnhance) {
        image = img.adjustColor(image, contrast: 1.2, brightness: 1.05);
        image = img.convolution(
          image,
          filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
        );
      }

      // Save enhanced image
      final tempDir = await getTemporaryDirectory();
      final enhancedPath =
          '${tempDir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(enhancedPath).writeAsBytes(img.encodeJpg(image, quality: 95));

      setState(() => _currentPath = enhancedPath);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Enhance'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSave(_currentPath);
              Navigator.pop(context);
            },
            child: Text(
              'Save',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.file(
                    File(_currentPath),
                    fit: BoxFit.contain,
                  ),
                  if (_isProcessing)
                    Container(
                      color: Colors.black54,
                      child: const CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Quick actions
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAction(
                  icon: Icons.auto_fix_high,
                  label: 'Auto',
                  isActive: _autoEnhance,
                  onTap: () {
                    setState(() => _autoEnhance = !_autoEnhance);
                    _applyEnhancements();
                  },
                ),
                _buildQuickAction(
                  icon: Icons.monochrome_photos,
                  label: 'B&W',
                  isActive: _grayscale,
                  onTap: () {
                    setState(() => _grayscale = !_grayscale);
                    _applyEnhancements();
                  },
                ),
                _buildQuickAction(
                  icon: Icons.rotate_right,
                  label: 'Rotate',
                  onTap: () {
                    // Rotate logic
                  },
                ),
                _buildQuickAction(
                  icon: Icons.crop,
                  label: 'Crop',
                  onTap: () {
                    // Crop logic
                  },
                ),
              ],
            ),
          ),

          // Sliders
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildSlider(
                    label: 'Brightness',
                    value: _brightness,
                    onChanged: (v) {
                      setState(() => _brightness = v);
                    },
                    onChangeEnd: (_) => _applyEnhancements(),
                  ),
                  _buildSlider(
                    label: 'Contrast',
                    value: _contrast,
                    onChanged: (v) {
                      setState(() => _contrast = v);
                    },
                    onChangeEnd: (_) => _applyEnhancements(),
                  ),
                  _buildSlider(
                    label: 'Saturation',
                    value: _saturation,
                    onChanged: (v) {
                      setState(() => _saturation = v);
                    },
                    onChangeEnd: (_) => _applyEnhancements(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withOpacity(0.2)
                  : Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive ? AppColors.primary : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppColors.primary : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: -100,
              max: 100,
              activeColor: AppColors.primary,
              inactiveColor: Colors.grey[700],
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value.toInt().toString(),
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// Scanned Pages Screen
class ScannedPagesScreen extends StatelessWidget {
  final List<ScannedPage> pages;
  final Function(int, int) onReorder;
  final Function(int) onDelete;
  final Function(ScannedPage) onEnhance;
  final VoidCallback onFinish;

  const ScannedPagesScreen({
    super.key,
    required this.pages,
    required this.onReorder,
    required this.onDelete,
    required this.onEnhance,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('${pages.length} Pages'),
        actions: [
          TextButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.check, color: AppColors.primary),
            label: const Text(
              'Done',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pages.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final page = pages[index];
          return Card(
            key: ValueKey(page.timestamp),
            color: const Color(0xFF1A1A1A),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(page.enhancedPath),
                  width: 50,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(
                'Page ${index + 1}',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Tap to enhance',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune, color: Colors.grey),
                    onPressed: () => onEnhance(page),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => onDelete(index),
                  ),
                  const Icon(Icons.drag_handle, color: Colors.grey),
                ],
              ),
              onTap: () => onEnhance(page),
            ),
          );
        },
      ),
    );
  }
}
