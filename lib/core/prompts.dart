import 'package:flutter/material.dart';

/// 通用文本输入对话框的字段定义。
class PromptField {
  const PromptField({
    required this.label,
    this.initial,
    this.hint,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final String? initial;
  final String? hint;
  final TextInputType? keyboardType;

  /// 返回错误提示文本；通过校验返回 null。
  final String? Function(String value)? validator;
}

/// 单字段文本输入对话框。
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  String confirmLabel = '确定',
  String? Function(String value)? validator,
}) async {
  final values = await showFieldsPrompt(
    context,
    title: title,
    confirmLabel: confirmLabel,
    fields: [
      PromptField(
        label: title,
        hint: hint,
        initial: initial,
        validator: validator,
      ),
    ],
  );
  return values?.firstOrNull;
}

/// 多字段文本输入对话框。
///
/// TextEditingController 由内部 StatefulWidget 持有，在对话框
/// （含关闭退场动画）真正卸载后才释放。禁止在 showDialog 的
/// Future 完成时同步 dispose controller —— 退场动画期间 TextField
/// 仍引用它，提前释放会导致 framework `_dependents.isEmpty` 断言崩溃。
Future<List<String>?> showFieldsPrompt(
  BuildContext context, {
  required String title,
  required List<PromptField> fields,
  String confirmLabel = '确定',
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _FieldsPromptDialog(
      title: title,
      fields: fields,
      confirmLabel: confirmLabel,
    ),
  );
}

class _FieldsPromptDialog extends StatefulWidget {
  const _FieldsPromptDialog({
    required this.title,
    required this.fields,
    required this.confirmLabel,
  });

  final String title;
  final List<PromptField> fields;
  final String confirmLabel;

  @override
  State<_FieldsPromptDialog> createState() => _FieldsPromptDialogState();
}

class _FieldsPromptDialogState extends State<_FieldsPromptDialog> {
  late final List<TextEditingController> _controllers;
  List<String?> _errors = const [];

  @override
  void initState() {
    super.initState();
    _controllers =
        widget.fields.map((f) => TextEditingController(text: f.initial)).toList();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = <String>[];
    final errors = <String?>[];
    var valid = true;
    for (var i = 0; i < widget.fields.length; i++) {
      final value = _controllers[i].text.trim();
      final error = widget.fields[i].validator?.call(value);
      if (error != null) valid = false;
      values.add(value);
      errors.add(error);
    }
    if (!valid) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.fields.length; i++) ...[
            TextField(
              controller: _controllers[i],
              autofocus: i == 0,
              keyboardType: widget.fields[i].keyboardType,
              decoration: InputDecoration(
                labelText: widget.fields[i].label,
                hintText: widget.fields[i].hint,
                errorText: _errors.isEmpty ? null : _errors[i],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
