import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/app_core.dart';
import '../chats/chat_screen.dart';
import '../media/media_utils.dart';
import '../widgets/common.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key, this.addToGid});
  /// When set, this screen adds members to an existing group instead of creating one.
  final String? addToGid;
  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final core = AppCore.I;
  final _sel = <String>{};
  int _step = 0;
  final _name = TextEditingController();
  Uint8List? _avatar;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final existing = widget.addToGid == null ? <String>{} : core.db.group(widget.addToGid!)!.members.keys.toSet();
    final contacts = core.db.contacts().where((c) => c.added > 0 && !c.blocked && !existing.contains(c.userId)).toList();
    if (_step == 1) return _details();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.addToGid == null ? 'New group' : 'Add members'),
          Text('${_sel.length} selected', style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
      body: contacts.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Add some contacts first.', textAlign: TextAlign.center)))
          : ListView(children: [
              for (final c in contacts)
                CheckboxListTile(
                  value: _sel.contains(c.userId),
                  onChanged: (v) => setState(() => v! ? _sel.add(c.userId) : _sel.remove(c.userId)),
                  secondary: Avatar(name: c.name, bytes: c.avatar),
                  title: Text(c.name),
                  subtitle: Text(c.about, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ]),
      floatingActionButton: _sel.isEmpty
          ? null
          : FloatingActionButton(
              child: Icon(widget.addToGid == null ? Icons.arrow_forward : Icons.check),
              onPressed: () async {
                if (widget.addToGid == null) return setState(() => _step = 1);
                await core.groups.addMembers(widget.addToGid!, _sel.toList());
                if (context.mounted) Navigator.pop(context);
              },
            ),
    );
  }

  Widget _details() => Scaffold(
        appBar: AppBar(title: const Text('New group')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (x == null) return;
                  final a = await MediaUtils.makeAvatar(x.path);
                  setState(() => _avatar = a);
                },
                child: CircleAvatar(
                  radius: 28,
                  backgroundImage: _avatar != null ? MemoryImage(_avatar!) : null,
                  child: _avatar == null ? const Icon(Icons.camera_alt) : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(controller: _name, autofocus: true, maxLength: 50,
                    decoration: const InputDecoration(hintText: 'Group name')),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Members: ${_sel.length + 1} (including you)'),
            const SizedBox(height: 8),
            const Text('Group messages are end-to-end encrypted with sender keys and delivered directly to each member when they are nearby.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey)),
          ]),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _busy
              ? null
              : () async {
                  if (_name.text.trim().isEmpty) return toast(context, 'Enter a group name');
                  setState(() => _busy = true);
                  final convId = await core.groups.create(_name.text, _sel.toList(), avatar: _avatar);
                  if (!mounted) return;
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(convId: convId)));
                },
          child: const Icon(Icons.check),
        ),
      );
}
