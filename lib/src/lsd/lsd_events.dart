import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';

abstract class LSDEvent {}

class LSDNewPeer implements LSDEvent {
  CompactAddress address;
  String infoHashHex;
  LSDNewPeer(
    this.address,
    this.infoHashHex,
  );
}
