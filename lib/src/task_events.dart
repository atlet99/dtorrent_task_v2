import 'package:dtorrent_task_v2/src/file/download_file.dart';
import 'package:dtorrent_task_v2/src/file/download_file_manager_events.dart';

abstract class TaskEvent {}

class TaskStopped implements TaskEvent {}

class TaskCompleted implements TaskEvent {}

class TaskPaused implements TaskEvent {}

class TaskResumed implements TaskEvent {}

class TaskStarted implements TaskEvent {}

class TaskFileCompleted implements TaskEvent {
  final DownloadFile file;
  TaskFileCompleted(
    this.file,
  );
}

class StateFileUpdated implements DownloadFileManagerEvent, TaskEvent {}

class AllComplete implements TaskEvent {}
