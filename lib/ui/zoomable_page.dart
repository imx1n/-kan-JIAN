import 'package:flutter/material.dart';

/// 单页：双击放大/还原，捏合缩放；未放大时不拦截左右翻页。
class ZoomablePage extends StatefulWidget {
  const ZoomablePage({super.key, required this.child, required this.onTapUp});

  final Widget child;
  final GestureTapUpCallback onTapUp;

  @override
  State<ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<ZoomablePage> with SingleTickerProviderStateMixin {
  final _t = TransformationController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _tween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() => _t.value = _tween!.value);
    _t.addListener(() {
      final z = _t.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _t.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final Matrix4 end;
    if (_zoomed) {
      end = Matrix4.identity();
    } else {
      const s = 2.5;
      final p = _doubleTapAt;
      end = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _tween = Matrix4Tween(begin: _t.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapUp: widget.onTapUp,
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _t,
          minScale: 1,
          maxScale: 4,
          panEnabled: _zoomed,
          child: SizedBox.expand(child: widget.child),
        ),
      );
}
