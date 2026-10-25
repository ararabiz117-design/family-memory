import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared white-glass surface. Clipping keeps the blur inside its bounds.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.tint,
    this.padding = EdgeInsets.zero,
    this.blur = 14,
  });

  final Widget child;
  final double radius;
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final double blur;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A33405E),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .90),
                (tint ?? const Color(0xFFF4F7FF)).withValues(alpha: .66),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .95)),
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.color, this.margin});
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin ?? EdgeInsets.zero,
    child: GlassSurface(tint: color, child: child),
  );
}

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0, .45, 1],
        colors: [Color(0xFFF5F8FF), Colors.white, Color(0xFFEDF6F6)],
      ),
    ),
    child: BackdropGroup(child: child),
  );
}

/// No artificial waiting: entrance motion starts when real content is ready.
class GlassEntrance extends StatelessWidget {
  const GlassEntrance({super.key, required this.child, this.order = 0});
  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + order.clamp(0, 8) * 25),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Use only while the corresponding data/image request is pending.
class GlassSkeleton extends StatefulWidget {
  const GlassSkeleton({
    super.key,
    this.height = 18,
    this.width,
    this.radius = 12,
  });
  final double height;
  final double? width;
  final double radius;

  @override
  State<GlassSkeleton> createState() => _GlassSkeletonState();
}

class _GlassSkeletonState extends State<GlassSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
      controller.value = .5;
    } else {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
            const Color(0xFFE5EBF3),
            const Color(0xFFF5F8FC),
            controller.value,
          ),
        ),
      ),
    ),
  );
}

class GlassScreenSkeleton extends StatelessWidget {
  const GlassScreenSkeleton({super.key, this.label = '読み込み中'});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: Scaffold(
      appBar: AppBar(title: const GlassSkeleton(width: 160, height: 24)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  const GlassSurface(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlassSkeleton(width: 150, height: 22),
                        SizedBox(height: 18),
                        GlassSkeleton(height: 16),
                        SizedBox(height: 10),
                        GlassSkeleton(width: 220, height: 16),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
