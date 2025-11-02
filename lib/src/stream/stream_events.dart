import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task.dart';

class StreamingServerStarted extends TaskEvent {
  final int port;
  final InternetAddress internetAddress;
  StreamingServerStarted({required this.port, required this.internetAddress});
}
