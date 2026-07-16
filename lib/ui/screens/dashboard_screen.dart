import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;

import '../../providers/vault_provider.dart';
import '../../providers/handshake_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'album_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  Color _currentBgColor = const Color(0xFF0F172A);
  Color _currentRippleBase = const Color(0xFFFF007F);
  Color _currentRippleHighlight = const Color(0xFFFF7EB3);
  Color _currentLightColor = Colors.white; // Added for Blinn-Phong glitter
  double _lightDirX = 0.0;
  double _lightDirY = -1.0;
  double _lightDirZ = 0.8;
  Timer? _bgTimer;
  
  // Rectangular Wake Physics
  late final AnimationController _ticker;
  final List<RectWake> _wakes = [];
  final Map<String, GlobalKey> _folderKeys = {};
  double _currentVelocity = 0.0;
  double _lastScrollDelta = 0.0;
  double _spawnTimer = 0;

  ui.FragmentProgram? _reflectionProgram;
  ui.Image? _cloudImage;
  bool _shaderFailed = false;

  ui.Image? _currentHeightmap;
  bool _isRenderingHeightmap = false;

  late AnimationController _cloudTicker; // Continuous ticker for background clouds

  @override
  void initState() {
    super.initState();
    _loadShaderAndAssets();
    _updateTimeAndColors();
    _bgTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateTimeAndColors();
    });

    _ticker = AnimationController(vsync: this, duration: const Duration(days: 365))
      ..addListener(_tick);
      
    // Drives the continuous cloud drift without triggering full UI rebuilds
    _cloudTicker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFolders();
    });
  }

  @override
  void dispose() {
    _bgTimer?.cancel();
    _ticker.dispose();
    _cloudTicker.dispose();
    _currentHeightmap?.dispose();
    _cloudImage?.dispose();
    super.dispose();
  }

  Future<void> _loadShaderAndAssets() async {
    try {
      _reflectionProgram = await ui.FragmentProgram.fromAsset('shaders/reflection.frag');
      final data = await DefaultAssetBundle.of(context).load('assets/clouds.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cloudImage = frame.image;
      
      // Render an initial blank heightmap so the clouds are visible immediately
      await _renderHeightmapAsync();
      
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Failed to load reflection shader or clouds: $e');
      _shaderFailed = true;
    }
  }

  void _updateTimeAndColors() {
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60.0;

    // Light direction computation (Sun/Moon arc)
    // 0 to 12 hours maps to 0 to pi (a semicircle overhead).
    // Shift by 6 hours so it rises at 6am/6pm and sets at 6pm/6am.
    final double sunMoonAngle = ((hour - 6.0) % 12.0) / 12.0 * math.pi;
    _lightDirX = -math.cos(sunMoonAngle); // goes from -1 (left) to 1 (right)
    _lightDirY = -math.sin(sunMoonAngle); // goes from 0 to -1 (up) back to 0
    _lightDirZ = 0.8; // constant depth

    // Premium sky color keyframes
    const nightBlue  = Color(0xFF060D1F);
    const dawnCoral  = Color(0xFFFF7E67); // Soft pinkish-orange sunrise
    const daySkyBlue = Color(0xFF38BDF8); // Vibrant azure sky blue
    const duskFiery  = Color(0xFFFF4B2B); // Deep fiery sunset orange/red

    final List<double> hours = [
      0.0, 4.5, 6.0, 8.5, 11.0, 15.0, 17.5, 20.0, 24.0,
    ];
    final List<Color> bgColors = [
      nightBlue, nightBlue, dawnCoral, daySkyBlue,
      daySkyBlue, daySkyBlue, duskFiery, nightBlue, nightBlue,
    ];

    // Ripple Colors
    const nightRippleBase = Color(0xFF38BDF8); 
    const nightRippleHigh = Color(0xFFBAE6FD);
    const dayRippleBase = Color(0xFFFF007F);
    const dayRippleHigh = Color(0xFFFF7EB3);

    final List<Color> rippleBases = [
      nightRippleBase, nightRippleBase, dayRippleBase, dayRippleBase,
      dayRippleBase, dayRippleBase, dayRippleBase, nightRippleBase, nightRippleBase,
    ];
    final List<Color> rippleHighs = [
      nightRippleHigh, nightRippleHigh, dayRippleHigh, dayRippleHigh,
      dayRippleHigh, dayRippleHigh, dayRippleHigh, nightRippleHigh, nightRippleHigh,
    ];

    // Glint & God-Rays Light Colors (Sun/Moon)
    final List<Color> lightColors = [
      const Color(0xFFBBDEFB), const Color(0xFFBBDEFB), // Night (Pale Moon Blue)
      const Color(0xFFFFB4A2), // Dawn (Soft Coral Sun to match the pink sky)
      const Color(0xFFFFF59D), const Color(0xFFFFF59D), const Color(0xFFFFF59D), // Day (Pale, softer sun yellow instead of harsh yellow)
      const Color(0xFFFF7A59), // Dusk (Soft Fiery/Pink Sun to match dusk sky)
      const Color(0xFFBBDEFB), const Color(0xFFBBDEFB), // Night (Pale Moon Blue)
    ];

    for (int i = 0; i < hours.length - 1; i++) {
      if (hour >= hours[i] && hour < hours[i + 1]) {
        final t = (hour - hours[i]) / (hours[i + 1] - hours[i]);
        // Smoothstep: accelerates gently in, decelerates gently out
        final smoothT = t * t * (3.0 - 2.0 * t);
        
        _currentBgColor = Color.lerp(bgColors[i], bgColors[i + 1], smoothT)!;
        _currentRippleBase = Color.lerp(rippleBases[i], rippleBases[i + 1], smoothT)!;
        _currentRippleHighlight = Color.lerp(rippleHighs[i], rippleHighs[i + 1], smoothT)!;
        _currentLightColor = Color.lerp(lightColors[i], lightColors[i + 1], smoothT)!;
        break;
      }
    }

    if (mounted) setState(() {});
  }

  void _tick() {
    bool active = false;

    // Spawn new wakes if scrolling
    if (_currentVelocity > 0.1) {
      // Ensure even ultra-slow drags build up the timer by giving it a minimum bump of 3.0.
      // Limit the max so fast flings don't over-spawn.
      _spawnTimer += math.min(math.max(_currentVelocity, 3.0), 12.0);
      // Spawn rate: Increased threshold to create more physical spacing between ripples
      if (_spawnTimer > 65) { 
        _spawnTimer = 0;
        _spawnWakesFromVisibleFolders();
      }
    }

    // Update active ripples
    for (int i = _wakes.length - 1; i >= 0; i--) {
      _wakes[i].update(_currentVelocity);
      if (_wakes[i].life <= 0) {
        _wakes.removeAt(i);
      } else {
        active = true;
      }
    }

    if (active || _currentVelocity > 0) {
      if (!_shaderFailed && _reflectionProgram != null && !_isRenderingHeightmap) {
        _renderHeightmapAsync();
      }
      setState(() {});
    } else {
      _ticker.stop();
    }
  }

  Future<void> _renderHeightmapAsync() async {
    _isRenderingHeightmap = true;
    
    // We need context.size but checking mounted is required for async gaps,
    // so we get MediaQuery early.
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    if (size.width == 0 || size.height == 0) {
      _isRenderingHeightmap = false;
      return;
    }

    // Half-resolution rendering
    final hw = (size.width / 2).ceil();
    final hh = (size.height / 2).ceil();
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, hw.toDouble(), hh.toDouble()));
    canvas.scale(0.5, 0.5); // scale down coordinate system

    // Black background (height 0)
    canvas.drawColor(Colors.black, BlendMode.src);

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0) // Softer blur for smoother ripples
      ..blendMode = BlendMode.screen;

    // We must pass a snapshot of the wakes since they might change during async wait.
    final wakesSnapshot = List<RectWake>.from(_wakes);

    for (final w in wakesSnapshot) {
      if (w.life <= 0) continue;
      // Fade in smoothly over the first ~10% of life to prevent popping in
      final fadeIn = math.min(1.0, (1.0 - w.life) * 10.0);
      final opacity = w.life.clamp(0.0, 1.0) * fadeIn;
      paint.color = Colors.white.withOpacity(opacity * 0.8);
      paint.strokeWidth = 20.0 + ((1.0 - w.life) * 10.0);
      
      final path = buildLiquidyPath(w.outerRect, w.life, waveCount: 4);
      canvas.drawPath(path, paint);
    }
    
    final picture = recorder.endRecording();
    final nextMap = await picture.toImage(hw, hh);
    
    if (mounted) {
      final old = _currentHeightmap;
      setState(() {
        _currentHeightmap = nextMap;
      });
      old?.dispose();
    } else {
      nextMap.dispose();
    }
    _isRenderingHeightmap = false;
  }

  void _spawnWakesFromVisibleFolders() {
    for (final key in _folderKeys.values) {
      if (key.currentContext != null) {
        final RenderBox? box = key.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final position = box.localToGlobal(Offset.zero);
          final rect = position & box.size;
          
          // Ensure we don't spawn wakes if the folder is completely off screen
          final screenHeight = MediaQuery.of(context).size.height;
          if (rect.bottom > 0 && rect.top < screenHeight) {
             _wakes.add(RectWake(baseRect: rect, moveDirection: _lastScrollDelta.sign));
          }
        }
      }
    }
  }

  Future<void> _loadFolders() async {
    final handshake = Provider.of<HandshakeProvider>(context, listen: false);
    final doc = handshake.couplesDocument;
    if (doc != null && doc.masterDriveFolderId != null) {
      await Provider.of<VaultProvider>(context, listen: false).fetchItems(doc.masterDriveFolderId!);
    }
  }

  Future<void> _showAddFolderDialog() async {
    final controller = TextEditingController();
    final vault = Provider.of<VaultProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundCream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('New Album', style: Theme.of(context).textTheme.headlineMedium),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Location Name',
              hintText: 'e.g., Udaipur',
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.burntOrange)),
              labelStyle: TextStyle(color: AppTheme.earthyBrown.withOpacity(0.7)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.earthyBrown)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final location = controller.text;
                if (location.isNotEmpty) {
                  final subfolderId = await vault.createSubfolder(location);
                  if (subfolderId != null && context.mounted) {
                     await _loadFolders();
                     final newFolder = vault.items.firstWhere(
                       (f) => f.id == subfolderId,
                       orElse: () => vault.items.first,
                     );
                     if (context.mounted) {
                       await Navigator.push(
                         context,
                         MaterialPageRoute(
                           builder: (context) => AlbumScreen(folder: newFolder),
                         ),
                       );
                       _loadFolders();
                     }
                  } else {
                     _loadFolders();
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Vault', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppTheme.earthyBrown)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.earthyBrown),
      ),
      drawer: const AppDrawer(),
      body: AnimatedContainer(
        duration: const Duration(seconds: 60),
        curve: Curves.linear,
        color: _currentBgColor,
        child: Stack(
          children: [
            // Solid Color Background (Night/Day transitioning)
            AnimatedContainer(
              duration: const Duration(seconds: 1),
              color: _currentBgColor,
            ),

            // Specular Cloud Reflection (Shader Layer)
            if (!_shaderFailed && _currentHeightmap != null && _cloudImage != null)
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  return Positioned.fill(
                    child: CustomPaint(
                      painter: RefractiveBackgroundPainter(
                        heightmap: _currentHeightmap,
                        cloudTexture: _cloudImage,
                        shaderProgram: _reflectionProgram,
                        cloudOpacity: settings.cloudOpacity,
                        lightDirX: _lightDirX,
                        lightDirY: _lightDirY,
                        lightDirZ: _lightDirZ,
                        lightColor: _currentLightColor,
                        bgColor: _currentBgColor,
                        repaint: _cloudTicker,
                      ),
                    ),
                  );
                },
              ),

            // Removed RectWakePainter from the main widget tree.
            // It is now rendered strictly offscreen to generate the `_currentHeightmap`
            // which powers the specular reflections in RefractiveBackgroundPainter.
            // The Scrollable Content
            SafeArea(
              child: Consumer<VaultProvider>(
                builder: (context, vault, child) {
                  if (vault.isLoading && vault.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.burntOrange));
                  }

                  if (vault.items.isEmpty) {
                    return Center(
                      child: Text(
                        'No albums yet.\nTap + to create one!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.earthyBrown.withOpacity(0.7)),
                      ),
                    );
                  }

                  return NotificationListener<ScrollUpdateNotification>(
                    onNotification: (notif) {
                      if (notif.scrollDelta != null) {
                        _currentVelocity = notif.scrollDelta!.abs();
                        _lastScrollDelta = notif.scrollDelta!;
                        if (!_ticker.isAnimating) _ticker.forward();
                      }
                      return false;
                    },
                    child: NotificationListener<ScrollEndNotification>(
                      onNotification: (notif) {
                        _currentVelocity = 0.0;
                        return false;
                      },
                      child: ListView.builder(
                        physics: const HeavyLiquidScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                        itemCount: vault.items.length,
                        itemBuilder: (context, index) {
                          final folder = vault.items[index];
                          final key = _folderKeys.putIfAbsent(folder.id ?? index.toString(), () => GlobalKey());

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24.0),
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.4, // Keep exactly 40% of screen width
                                child: _buildVerticalFolderCard(folder, vault, key),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFolderDialog,
        backgroundColor: AppTheme.burntOrange,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVerticalFolderCard(folder, VaultProvider vault, GlobalKey key) {
    return Container(
      key: key, // We track exactly this box to spawn the rectangular wake!
      child: AspectRatio(
        aspectRatio: 0.75, // Vertical 'boat' shape constraint
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.earthyBrown.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () async {
                // Spawn a tiny tap-wake before navigating
                _wakes.add(RectWake(
                   baseRect: (key.currentContext?.findRenderObject() as RenderBox?)!.localToGlobal(Offset.zero) & 
                         (key.currentContext?.findRenderObject() as RenderBox?)!.size,
                   moveDirection: 0.0,
                ));
                if (!_ticker.isAnimating) _ticker.forward();

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AlbumScreen(folder: folder),
                  ),
                );
                _loadFolders();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top section: Thumbnail image
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                      child: FolderThumbnailWidget(folderId: folder.id ?? ''),
                    ),
                  ),
                  // Bottom section: Folder title and delete button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            folder.name ?? 'Untitled Album',
                            maxLines: 1, // Fixes vertical overflow
                            overflow: TextOverflow.ellipsis, // Uses "..." for long text
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 20, color: AppTheme.earthyBrown.withOpacity(0.5)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: AppTheme.backgroundCream,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: Text('Delete Album?', style: Theme.of(context).textTheme.headlineMedium),
                                content: const Text('This will delete the folder and all photos inside it from Google Drive.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppTheme.earthyBrown))),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true), 
                                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await vault.deleteItem(folder.id!);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Stateful Widget that asynchronously fetches and displays the first image in a folder.
class FolderThumbnailWidget extends StatefulWidget {
  final String folderId;
  const FolderThumbnailWidget({super.key, required this.folderId});

  @override
  State<FolderThumbnailWidget> createState() => _FolderThumbnailWidgetState();
}

class _FolderThumbnailWidgetState extends State<FolderThumbnailWidget> {
  MemoryImage? _thumbnail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchThumbnail();
  }

  Future<void> _fetchThumbnail() async {
    final vault = Provider.of<VaultProvider>(context, listen: false);
    final image = await vault.fetchFolderThumbnail(widget.folderId);
    
    if (mounted) {
      setState(() {
        _thumbnail = image;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: AppTheme.backgroundCream.withOpacity(0.3),
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.burntOrange, strokeWidth: 2),
        ),
      );
    }
    
    if (_thumbnail != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black12,
          image: DecorationImage(
            image: _thumbnail!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Fallback if folder is empty or no images found
    return Container(
      color: AppTheme.backgroundCream.withOpacity(0.6),
      child: Center(
        child: Icon(
          Icons.photo_album_rounded, 
          size: 48, 
          color: AppTheme.burntOrange.withOpacity(0.7)
        ),
      ),
    );
  }
}


/// A Wake that expands outwards as a rounded rectangle from the folder boundaries.
class RectWake {
  final Rect baseRect;
  final double moveDirection; // 1.0 for UP, -1.0 for DOWN, 0.0 for stationary
  double currentExpansion;
  double life; // 1.0 down to 0.0

  RectWake({required this.baseRect, required this.moveDirection}) : life = 1.0, currentExpansion = 0.0;

  void update(double velocityAbs) {
    // Less viscous fluid: expands faster and fades slower
    double clampedVelocity = math.min(velocityAbs, 10.0);
    currentExpansion += 0.55 + (clampedVelocity * 0.022); 
    life -= 0.002; 
  }
  
  Rect get outerRect {
    // Doppler Effect: Compress the front, stretch the back heavily (Softened slightly for thick fluid)
    double topExp = currentExpansion * (moveDirection > 0 ? 0.3 : (moveDirection < 0 ? 2.0 : 1.0));
    double bottomExp = currentExpansion * (moveDirection > 0 ? 2.0 : (moveDirection < 0 ? 0.3 : 1.0));
    return Rect.fromLTRB(
      baseRect.left - currentExpansion,
      baseRect.top - topExp,
      baseRect.right + currentExpansion,
      baseRect.bottom + bottomExp,
    );
  }
  
  // The inner echo ring expands slightly slower than the outer ring, creating a gap, 
  // but it NEVER goes smaller than the original base folder size.
  Rect get innerRect {
    double innerExp = math.max(0.0, currentExpansion - 15.0); // Wider gap for thicker fluid
    double topExp = innerExp * (moveDirection > 0 ? 0.3 : (moveDirection < 0 ? 2.0 : 1.0));
    double bottomExp = innerExp * (moveDirection > 0 ? 2.0 : (moveDirection < 0 ? 0.3 : 1.0));
    return Rect.fromLTRB(
      baseRect.left - innerExp,
      baseRect.top - topExp,
      baseRect.right + innerExp,
      baseRect.bottom + bottomExp,
    );
  }
}

/// Builds a distorted superellipse path. `waveCount` controls how many
/// ripple crests appear around the perimeter — higher = tighter shimmer.
Path buildLiquidyPath(Rect rect, double life, {int waveCount = 8}) {
  final path = Path();
  final w = rect.width / 2;
  final h = rect.height / 2;
  final cx = rect.center.dx;
  final cy = rect.center.dy;

  const double n = 3.0; // Slightly more oval, smoother corners
  final amplitude = (1.0 - life) * 12.0; // Restored to a moderate amplitude
  final phase = (1.0 - life) * -15.0; // Slower phase shift

  const int steps = 100;
  for (int i = 0; i <= steps; i++) {
    final theta = (i / steps) * 2 * math.pi;
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);

    final sx = w * cosT.sign * math.pow(cosT.abs(), 2 / n);
    final sy = h * sinT.sign * math.pow(sinT.abs(), 2 / n);

    final sineWave = math.sin(waveCount * theta + phase);
    final outwardDistort = amplitude * ((sineWave + 1.0) / 2.0);

    final px = cx + sx + (cosT * outwardDistort);
    final py = cy + cy * 0 + sy + (sinT * outwardDistort);

    if (i == 0) {
      path.moveTo(px, py);
    } else {
      path.lineTo(px, py);
    }
  }
  path.close();
  return path;
}

class RefractiveBackgroundPainter extends CustomPainter {
  final ui.Image? heightmap;
  final ui.Image? cloudTexture;
  final ui.FragmentProgram? shaderProgram;
  final double cloudOpacity;
  final double lightDirX;
  final double lightDirY;
  final double lightDirZ;
  final Color lightColor;
  final Color bgColor;

  RefractiveBackgroundPainter({
    required this.heightmap,
    required this.cloudTexture,
    required this.shaderProgram,
    required this.cloudOpacity,
    required this.lightDirX,
    required this.lightDirY,
    required this.lightDirZ,
    required this.lightColor,
    required this.bgColor,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (heightmap == null || cloudTexture == null || shaderProgram == null) return;

    final shader = shaderProgram!.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, heightmap!.width.toDouble());
    shader.setFloat(3, heightmap!.height.toDouble());
    shader.setFloat(4, cloudTexture!.width.toDouble());
    shader.setFloat(5, cloudTexture!.height.toDouble());
    // Use modulo to keep the time value small, preventing 32-bit float precision loss
    // which was swallowing the fractional uv.x coordinate and causing horizontal stretching.
    final timeVal = (DateTime.now().millisecondsSinceEpoch % 1000000) / 1000.0;
    shader.setFloat(6, timeVal); // u_time
    shader.setFloat(7, cloudOpacity); // u_cloudOpacity
    shader.setFloat(8, lightDirX);
    shader.setFloat(9, lightDirY);
    shader.setFloat(10, lightDirZ);
    shader.setFloat(11, lightColor.red / 255.0);
    shader.setFloat(12, lightColor.green / 255.0);
    shader.setFloat(13, lightColor.blue / 255.0);
    shader.setFloat(14, bgColor.red / 255.0);
    shader.setFloat(15, bgColor.green / 255.0);
    shader.setFloat(16, bgColor.blue / 255.0);
    
    shader.setImageSampler(0, heightmap!);
    shader.setImageSampler(1, cloudTexture!);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true; // heightmap changes every frame
}

/// Paints true liquid, refractive "boat wakes" using custom procedural geometry.
class RectWakePainter extends CustomPainter {
  final List<RectWake> wakes;
  final Color baseColor;
  final Color highlightColor;

  RectWakePainter({
    required this.wakes,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final causticSpecularColor = Colors.white;

    for (var w in wakes) {
      if (w.life <= 0) continue;

      // Fade in smoothly over the first ~10% of life to prevent popping in
      final fadeIn = math.min(1.0, (1.0 - w.life) * 10.0);
      final opacity = w.life.clamp(0.0, 1.0) * fadeIn;
      // Use an EVEN waveCount to guarantee perfect left-right symmetry, but higher for more "ripples"
      final outerPath = buildLiquidyPath(w.outerRect, w.life, waveCount: 6);

      // ── 1. Water-body fill ──────────────────────────────────────────────
      // Very subtle fill inside the ring simulates the volume of a water surface.
      canvas.drawPath(outerPath, Paint()
        ..color = baseColor.withOpacity((opacity * 0.1).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill,
      );

      // ── 2. Main caustic stroke ──────────────────────────────────────────
      canvas.drawPath(outerPath, Paint()
        ..color = baseColor.withOpacity((opacity * 0.8).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + ((1.0 - w.life) * 2.0) 
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0), // Softer, smoother boundary
      );

      // ── 3. Bright caustic highlight ─────────────────────────────────────
      canvas.drawPath(outerPath, Paint()
        ..color = highlightColor.withOpacity((opacity * 0.95).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 // Thinner highlight
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
      );

      // ── 4. Specular shimmer ─────────────────────────────────────────────
      // Higher wave frequency for more shimmer ripples
      canvas.drawPath(
        buildLiquidyPath(w.outerRect, w.life, waveCount: 8),
        Paint()
          ..color = causticSpecularColor.withOpacity((opacity * 0.6).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5), // Softer shimmer
      );

      // ── 5. Inner echo ring ──────────────────────────────────────────────
      // Wait to draw the echo ring until the outer ring expands a bit
      final innerRect = w.innerRect;
      if (innerRect.width > 0 && innerRect.height > 0) {
        final innerLife    = math.min(1.0, w.life + 0.3);
        final innerOpacity = opacity * 0.45;
        // Inner ring
        final innerPath    = buildLiquidyPath(innerRect, innerLife, waveCount: 4);

        canvas.drawPath(innerPath, Paint()
          ..color = baseColor.withOpacity(innerOpacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5), // Softer inner boundary
        );

        canvas.drawPath(innerPath, Paint()
          ..color = highlightColor.withOpacity((innerOpacity * 0.8).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 // Thinner inner highlight
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant RectWakePainter oldDelegate) => true;
}

/// Custom ScrollPhysics that makes the list feel heavy, like moving objects through dense liquid.
/// It heavily dampens both direct drag speed and fling momentum.
class HeavyLiquidScrollPhysics extends BouncingScrollPhysics {
  const HeavyLiquidScrollPhysics({super.parent});

  @override
  HeavyLiquidScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HeavyLiquidScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 2/3 as viscous: increases multiplier from 0.2 to 0.3
    return super.applyPhysicsToUserOffset(position, offset * 0.3);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // 2/3 as viscous: increases momentum multiplier from 0.15 to 0.225
    return super.createBallisticSimulation(position, velocity * 0.225);
  }
}
