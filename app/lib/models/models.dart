import 'dart:convert';
import 'dart:typed_data';

class Contact {
  Contact({required this.userId, required this.edPk, required this.name, this.avatar, this.verified = false,
      this.blocked = false, this.lastSeen = 0, this.added = 0, this.about = ''});
  final String userId;
  final Uint8List edPk;
  String name;
  Uint8List? avatar;
  bool verified, blocked;
  int lastSeen, added;
  String about;
  String get initials => name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
}

class Conversation {
  Conversation({required this.id, required this.kind, this.peerId, this.groupId, required this.title,
      this.lastMsgTs = 0, this.lastPreview = '', this.unread = 0, this.muted = false, this.disappearingSecs = 0,
      this.archived = false, this.pinned = false});
  final String id;
  final String kind; // 'direct' | 'group'
  final String? peerId;
  final String? groupId;
  String title;
  int lastMsgTs;
  String lastPreview;
  int unread;
  bool muted, archived, pinned;
  int disappearingSecs;
  bool get isGroup => kind == 'group';
}

class Message {
  Message({required this.id, required this.convId, required this.senderId, required this.ts, required this.kind,
      required this.body, this.status = 'pending', this.attachmentId, this.replyTo, this.expiresAt, this.deleted = false,
      this.reactions = const {}});
  final String id, convId, senderId;
  final int ts;
  String kind;
  Map<String, dynamic> body;
  String status;
  String? attachmentId, replyTo;
  int? expiresAt;
  bool deleted;
  Map<String, String> reactions; // userId -> emoji
  String get text => body['text'] as String? ?? '';
  String get bodyJson => jsonEncode(body);

  String preview() {
    switch (kind) {
      case 'text': return text;
      case 'image': return '📷 Photo';
      case 'video': return '🎥 Video';
      case 'audio': return '🎤 Voice message';
      case 'doc': return '📄 ${body['name'] ?? 'Document'}';
      case 'location': return '📍 Location';
      case 'live_location': return '📍 Live location';
      case 'contact': return '👤 ${body['name'] ?? 'Contact'}';
      case 'call': return body['missed'] == true ? '📵 Missed call' : '📞 Call';
      case 'deleted': return '🚫 Message deleted';
      default: return text;
    }
  }
}

class Attachment {
  Attachment({required this.id, required this.fileId, required this.name, required this.mime, required this.size,
      required this.key, required this.hash, required this.chunks, this.localPath, this.receivedChunks = 0,
      this.state = 'pending', this.thumb});
  final String id;          // == fileId b64
  final Uint8List fileId, key, hash;
  final String name, mime;
  final int size, chunks;
  String? localPath;        // encrypted-at-rest blob path
  int receivedChunks;
  String state;             // pending | transferring | done | failed
  Uint8List? thumb;         // small jpeg
  double get progress => chunks == 0 ? 1 : receivedChunks / chunks;
  bool get done => state == 'done';
}

class GroupInfo {
  GroupInfo({required this.gid, required this.name, required this.version, required this.created,
      required this.members, required this.admins, this.avatar});
  final String gid; // b64
  String name;
  int version;
  final int created;
  Map<String, Uint8List> members;
  List<String> admins;
  Uint8List? avatar;
}

class StatusPost {
  StatusPost({required this.id, required this.authorId, required this.ts, required this.expires, required this.kind,
      required this.body, this.attachmentId, this.seen = false, this.viewers = const []});
  final String id, authorId, kind; // kind: text | image | video
  final int ts, expires;
  final Map<String, dynamic> body; // text, bg color, caption
  final String? attachmentId;
  bool seen;
  List<String> viewers;
  bool get expired => DateTime.now().millisecondsSinceEpoch > expires;
}

class CallLog {
  CallLog({required this.id, required this.peerId, required this.ts, required this.outgoing, required this.answered,
      this.duration = 0, this.video = false});
  final String id, peerId;
  final int ts, duration;
  final bool outgoing, answered, video;
}

class DiscoveredPeer {
  DiscoveredPeer({required this.userId, required this.name, this.host, this.port, required this.via, required this.seenAt});
  final String userId, name;
  final String? host;
  final int? port;
  final String via; // mdns | udp | wifidirect | multipeer
  final int seenAt;
}
