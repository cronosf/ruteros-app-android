import 'package:flutter/material.dart';
import '../../core/report_types.dart';

Future<void> showReportSheet(BuildContext context, void Function(String typeCode, String? comment) onSubmit) {
  final commentCtrl = TextEditingController();
  String selected = reportTypes.first.code;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Reportar en esta ubicacion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reportTypes
                    .map((t) => ChoiceChip(
                          label: Text(t.label),
                          avatar: Icon(t.icon, size: 18, color: t.color),
                          selected: selected == t.code,
                          onSelected: (_) => setState(() => selected = t.code),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(labelText: 'Comentario (opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  onSubmit(selected, commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim());
                  Navigator.of(ctx).pop();
                },
                child: const Text('Enviar reporte'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
