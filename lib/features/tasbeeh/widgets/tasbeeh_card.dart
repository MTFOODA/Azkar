import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/asymmetric_card.dart';
import '../../content/domain/content_item.dart';
import '../../content/widgets/content_style.dart';
import '../domain/tasbeeh_counter.dart';

/// An independent, locally persisted Tasbeeh counter card.
///
/// No target, no maximum, no server counter. The counter state is owned by this
/// widget (and the [TasbeehCounter] engine), so an increment never rebuilds the
/// rest of the homepage.
class TasbeehCard extends ConsumerStatefulWidget {
  const TasbeehCard({
    super.key,
    required this.item,
    this.pageId,
    this.preview = false,
  });

  final ContentItem item;
  final String? pageId;
  final bool preview;

  @override
  ConsumerState<TasbeehCard> createState() => _TasbeehCardState();
}

class _TasbeehCardState extends ConsumerState<TasbeehCard> {
  TasbeehCounter? _counter;
  BigInt _value = BigInt.zero;
  bool _ready = false;
  int _animationTick = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.preview) _createCounter();
  }

  @override
  void didUpdateWidget(covariant TasbeehCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.pageId != widget.pageId) {
      _counter?.dispose();
      _counter = null;
      _ready = false;
      _value = BigInt.zero;
      if (!widget.preview) _createCounter();
    }
  }

  void _createCounter() {
    final store = ref.read(tasbeehCounterStoreProvider);
    final counter = TasbeehCounter(
      store: store,
      tasbeehId: widget.item.id,
      pageId: widget.pageId,
      onChanged: (value) {
        if (!mounted) return;
        setState(() {
          _value = value;
          _ready = true;
          _animationTick++;
        });
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      },
    );
    _counter = counter;
    counter.load();
  }

  @override
  void dispose() {
    _counter?.dispose();
    super.dispose();
  }

  void _increment() {
    if (widget.preview) {
      setState(() {
        _value += BigInt.one;
        _animationTick++;
      });
      return;
    }
    _counter?.increment();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تصفير العدّاد'),
        content: const Text('هل تريد تصفير عدّاد هذا التسبيح فقط؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تصفير'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.preview) {
      setState(() => _value = BigInt.zero);
    } else {
      await _counter?.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.item.style;
    final background = style.backgroundColorValue;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AsymmetricCard(
      shape: style.shape,
      backgroundColor: background,
      decorationColor: style.textColorValue,
      showDecoration: style.decorationEnabled,
      borderColor: style.textColorValue.withValues(alpha: 0.35),
      showBorder: style.borderEnabled,
      semanticLabel: 'تسبيح ${widget.item.arabicText}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArabicText(
            widget.item.arabicText,
            style: ContentStyleResolver.textStyle(style),
            textAlign: style.textAlignment,
          ),
          const SizedBox(height: AppPalette.spaceLg),
          Semantics(
            label: 'العدّاد الحالي',
            value: _value.toString(),
            child: AnimatedSwitcher(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Text(
                _value.toString(),
                key: ValueKey<int>(_animationTick),
                textAlign: TextAlign.center,
                style: ContentStyleResolver.textStyle(
                  style,
                  fontSize: 42,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppPalette.spaceLg),
          Semantics(
            button: true,
            label: 'تسبيح، يزيد العدّاد واحدًا',
            child: FilledButton(
              onPressed: _ready || widget.preview ? _increment : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('تسبيح +'),
            ),
          ),
          const SizedBox(height: AppPalette.spaceSm),
          TextButton.icon(
            onPressed: _ready || widget.preview ? _reset : null,
            icon: const Icon(Icons.restart_alt_outlined),
            label: const Text('تصفير'),
          ),
          if (!_ready && !widget.preview)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('استعادة العدّاد…', textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
