import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Shrinks slightly while pressed and springs back, like native list cells and cards.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap == null || _down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and slides a list item in once, staggered by [index].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 16});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 45 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _curve.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Animated placeholder shown while content loads, shaped like the content it replaces.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 3 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: const [Color(0x0FFFFFFF), Color(0x1FFFFFFF), Color(0x0FFFFFFF)],
            ),
          ),
        );
      },
    );
  }
}

/// A card-shaped skeleton matching the reservation cards.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Skeleton(width: 48, height: 48, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(width: 140, height: 16),
                  SizedBox(height: 8),
                  Skeleton(width: 90),
                  SizedBox(height: 6),
                  Skeleton(width: 120),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonList extends SliverPadding {
  SkeletonList({super.key, int count = 3})
    : super(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverList.separated(
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, _) => const SkeletonCard(),
        ),
      );
}

/// Number that counts to its new value instead of jumping.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount(this.value, {super.key, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Pill tabs with a red indicator that slides between options, like the website's tabs.
class HubSegmentedControl<T> extends StatelessWidget {
  const HubSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.isEnabled,
  });

  final List<(T, String)> segments;

  /// May be a value that isn't in [segments] to show nothing selected.
  final T? selected;
  final ValueChanged<T> onChanged;
  final bool Function(T value)? isEnabled;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final index = segments.indexWhere((s) => s.$1 == selected);

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: HubColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / segments.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                left: width * (index < 0 ? 0 : index),
                top: 0,
                bottom: 0,
                width: width,
                child: AnimatedOpacity(
                  opacity: index < 0 ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: HubColors.red,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [BoxShadow(color: HubColors.red.withValues(alpha: 0.35), blurRadius: 14)],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (value, label) in segments)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: value == selected || !(isEnabled?.call(value) ?? true)
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                onChanged(value);
                              },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: text.labelLarge!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: value == selected
                                  ? Colors.white
                                  : (isEnabled?.call(value) ?? true)
                                  ? HubColors.textSecondary
                                  : HubColors.textMuted.withValues(alpha: 0.5),
                            ),
                            child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The website's soft red glow behind page content.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, required this.child, this.intensity = 0.14});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -220,
          left: -120,
          right: -120,
          height: 480,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    HubColors.red.withValues(alpha: intensity),
                    HubColors.red.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Translucent blurred surface for bars that content scrolls underneath.
class Frosted extends StatelessWidget {
  const Frosted({super.key, required this.child, this.color = const Color(0xB3020618), this.border});

  final Widget child;
  final Color color;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, border: border),
          child: child,
        ),
      ),
    );
  }
}

/// Wraps each child in a [FadeSlideIn] with increasing delay.
List<Widget> staggered(List<Widget> children) => [
  for (final (i, child) in children.indexed) FadeSlideIn(index: i, child: child),
];
