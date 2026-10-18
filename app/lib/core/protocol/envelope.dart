/// Envelope type strings exchanged inside the E2EE channel (ptype 1).
class Env {
  static const profile = 'profile';
  static const chat = 'chat';
  static const ack = 'ack';
  static const typing = 'typing';
  static const fileReq = 'file.req';
  static const fileDone = 'file.done';
  static const groupState = 'group.state';
  static const groupSenderKey = 'group.skey';
  static const groupMsg = 'group.msg';
  static const statusSync = 'status.sync';
  static const statusPost = 'status.post';
  static const statusSeen = 'status.seen';
  static const callOffer = 'call.offer';
  static const callAnswer = 'call.answer';
  static const callIce = 'call.ice';
  static const callEnd = 'call.end';
  static const callBusy = 'call.busy';
  static const locationLive = 'location.live';
  static const delete = 'delete';
  static const reaction = 'reaction';
}

/// Message kinds (what a chat bubble renders).
class MsgKind {
  static const text = 'text';
  static const image = 'image';
  static const video = 'video';
  static const audio = 'audio';
  static const doc = 'doc';
  static const location = 'location';
  static const liveLocation = 'live_location';
  static const contact = 'contact';
  static const system = 'system';
  static const call = 'call';
  static const deleted = 'deleted';
  static bool hasAttachment(String k) => k == image || k == video || k == audio || k == doc;
}

class MsgStatus {
  static const pending = 'pending';
  static const sent = 'sent';
  static const delivered = 'delivered';
  static const read = 'read';
  static const failed = 'failed';
}
