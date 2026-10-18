import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';

class TextStatusScreen extends StatefulWidget {
  const TextStatusScreen({super.key});
  @override
  State<TextStatusScreen> createState() => _TextStatusScreenState();
}

class _TextStatusScreenState extends State<TextStatusScreen> {
  static const _colors = [0xFF008069, 0xFF5E35B1, 0xFFD81B60, 0xFFF4511E, 0xFF3949AB, 0xFF00897B, 0xFF6D4C41, 0xFF263238];
  int _c = 0;
  final _t = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Color(_colors[_c]),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(icon: const Icon(Icons.palette), onPressed: () => setState(() => _c = (_c + 1) % _colors.length)),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              controller: _t, autofocus: true, maxLines: null, maxLength: 700, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 30),
              cursorColor: Colors.white,
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Type a status',
                  hintStyle: TextStyle(color: Colors.white60), counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        floatingActionButton: _t.text.trim().isEmpty
            ? null
            : FloatingActionButton(
                child: const Icon(Icons.send),
                onPressed: () async {
                  await AppCore.I.status.postText(_t.text.trim(), _colors[_c]);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
      );
}
