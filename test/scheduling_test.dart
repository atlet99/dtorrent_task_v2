import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

class _FakeSchedulerDelegate implements SchedulerDelegate {
  int pauses = 0;
  int resumes = 0;
  int clears = 0;
  int? downloadLimit;
  int? uploadLimit;

  @override
  void applySpeedLimits({int? maxDownloadRate, int? maxUploadRate}) {
    downloadLimit = maxDownloadRate;
    uploadLimit = maxUploadRate;
  }

  @override
  void clearSpeedLimits() {
    clears++;
    downloadLimit = null;
    uploadLimit = null;
  }

  @override
  void pauseTask() {
    pauses++;
  }

  @override
  void resumeTask() {
    resumes++;
  }
}

void main() {
  group('Scheduling (5.3)', () {
    test('should resume and apply limits inside active window', () {
      var now = DateTime(2026, 4, 21, 10, 0); // Tuesday
      final delegate = _FakeSchedulerDelegate();
      final scheduler = TaskScheduler(
        delegate: delegate,
        clock: () => now,
      );

      scheduler.addWindow(
        const ScheduleWindow(
          id: 'work',
          weekdays: {1, 2, 3, 4, 5},
          start: Duration(hours: 9),
          end: Duration(hours: 18),
          maxDownloadRate: 1024,
          maxUploadRate: 512,
        ),
      );
      scheduler.start(tick: const Duration(hours: 1));

      expect(delegate.resumes, greaterThan(0));
      expect(delegate.downloadLimit, 1024);
      expect(delegate.uploadLimit, 512);

      scheduler.dispose();
    });

    test('should pause outside window when pauseOutsideWindow enabled', () {
      var now = DateTime(2026, 4, 21, 23, 0); // Tuesday
      final delegate = _FakeSchedulerDelegate();
      final scheduler = TaskScheduler(
        delegate: delegate,
        clock: () => now,
      );

      scheduler.addWindow(
        const ScheduleWindow(
          id: 'night-lock',
          weekdays: {1, 2, 3, 4, 5, 6, 7},
          start: Duration(hours: 9),
          end: Duration(hours: 18),
          pauseOutsideWindow: true,
        ),
      );
      scheduler.start(tick: const Duration(hours: 1));

      expect(delegate.pauses, greaterThan(0));
      expect(delegate.downloadLimit, isNull);
      expect(delegate.uploadLimit, isNull);

      scheduler.dispose();
    });
  });
}
