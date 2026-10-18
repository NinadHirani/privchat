import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../widgets/common.dart';

class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key, required this.msgId});
  final String msgId;
  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final _sel = <String>{};
  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final convs = core.db.conversations().where((c) => !(c.isGroup && core.db.groupLeft(c.groupId!))).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Forward to…')),
      body: ListView(children: [
        for (final c in convs)
          CheckboxListTile(
            value: _sel.contains(c.id),
            onChanged: (v) => setState(() => v! ? _sel.add(c.id) : _sel.remove(c.id)),
            secondary: Avatar(name: c.title, group: c.isGroup,
                bytes: c.isGroup ? core.db.group(c.groupId!)?.avatar : core.avatarOf(c.peerId!)),
            title: Text(c.isGroup ? c.title : core.nameOf(c.peerId!)),
          ),
      ]),
      floatingActionButton: _sel.isEmpty
          ? null
          : FloatingActionButton(
              child: const Icon(Icons.send),
              onPressed: () async {
                for (final id in _sel) {
                  await core.messages.forward(widget.msgId, id);
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
    );
  }
}
