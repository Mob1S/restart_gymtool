import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/files/beverage_ocr.dart';
import '../../domain/beverage.dart';
import '../../domain/beverage_label_parser.dart';
import '../../ui/tokens.dart';
import 'beverage_form.dart';

class BeverageEditorPage extends StatefulWidget {
  final Beverage? initial;
  final bool? scanCamera;
  const BeverageEditorPage({super.key, this.initial, this.scanCamera});
  @override
  State<BeverageEditorPage> createState() => _BeverageEditorPageState();
}

class _BeverageEditorPageState extends State<BeverageEditorPage> {
  var _key = GlobalKey<BeverageFormState>();
  final _ocr = BeverageOcr();
  Uint8List? _image;
  BeverageLabelDraft? _draft;
  String? _message, _raw;
  bool _scanning = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.scanCamera != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scan(widget.scanCamera!),
      );
    }
  }

  Future<void> _scan(bool camera) async {
    final generation = ++_generation;
    setState(() {
      _scanning = true;
      _message = null;
    });
    try {
      final scan = await _ocr.scan(camera: camera);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (scan != null) {
          _image = scan.image;
          _raw = scan.text;
          _draft = parseBeverageLabel(scan.text);
          _key = GlobalKey<BeverageFormState>();
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = '图片识别未完成。请重试清晰的标签照片；当前设备可能不支持拍照或本地识别。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _scanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial == null ? '添加饮料 · 核对资料' : '编辑饮料资料'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      children: [
        if (_scanning) ...[
          const LinearProgressIndicator(),
          const Text('在设备上识别标签，原图不会上传。首次识别可能需要一些时间。'),
          TextButton(
            onPressed: () {
              ++_generation;
              _ocr.cancel();
              setState(() => _scanning = false);
            },
            child: const Text('取消识别'),
          ),
        ],
        if (_message != null)
          Text(
            _message!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton.icon(
              onPressed: _scanning ? null : () => _scan(false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('导入标签图片'),
            ),
            TextButton.icon(
              onPressed: _scanning ? null : () => _scan(true),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('拍摄标签'),
            ),
          ],
        ),
        if (_image != null) ...[
          Image.memory(_image!, height: 240, fit: BoxFit.contain),
          ExpansionTile(
            title: const Text('查看识别文字'),
            children: [SelectableText(_raw ?? '')],
          ),
          Text(_draft!.warning),
          const SizedBox(height: AppSpacing.lg),
        ],
        // Recreate only after a scan has completed, never while editing or on a
        // failed/cancelled scan, so manually entered values survive errors.
        KeyedSubtree(
          key: ValueKey(_draft),
          child: BeverageForm(
            key: _key,
            initial: widget.initial,
            initialEnergy: _draft?.energy,
            initialName: _draft?.name,
            initialVolume: _draft?.volumeMl,
            initialUnit: _draft?.unit,
            initialBasis: _draft?.basis,
            labelScan: _draft != null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _scanning
              ? null
              : () {
                  try {
                    final value = _key.currentState!.value();
                    if (value != null) Navigator.of(context).pop(value);
                  } catch (e) {
                    setState(() => _message = '$e');
                  }
                },
          child: const Text('确认资料'),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    ),
  );
  @override
  void dispose() {
    _generation++;
    _ocr.cancel();
    _image = null;
    super.dispose();
  }
}
