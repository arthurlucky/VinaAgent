import 'package:flutter_test/flutter_test.dart';
import 'package:pocketstrike/features/agent/data/cron_task_store.dart';

void main() {
  group('nextCronRunAt', () {
    test('daily schedule fires later the same day when still ahead', () {
      final from = DateTime(2026, 11, 5, 6, 0);
      expect(
        nextCronRunAt('daily@07:00', from),
        DateTime(2026, 11, 5, 7, 0),
      );
    });

    test('daily schedule rolls over to tomorrow when the time has passed', () {
      final from = DateTime(2026, 11, 5, 8, 0);
      expect(
        nextCronRunAt('daily@07:00', from),
        DateTime(2026, 11, 6, 7, 0),
      );
    });

    test('daily schedule rolls over when the time is exactly now', () {
      final from = DateTime(2026, 11, 5, 7, 0);
      expect(
        nextCronRunAt('daily@07:00', from),
        DateTime(2026, 11, 6, 7, 0),
      );
    });

    test('legacy daily_7am label maps to 07:00', () {
      final from = DateTime(2026, 11, 5, 8, 0);
      expect(
        nextCronRunAt('daily_7am', from),
        DateTime(2026, 11, 6, 7, 0),
      );
    });

    test('hourly and every_30m add their interval', () {
      final from = DateTime(2026, 11, 5, 8, 0);
      expect(nextCronRunAt('hourly', from), DateTime(2026, 11, 5, 9, 0));
      expect(
        nextCronRunAt('every_30m', from),
        DateTime(2026, 11, 5, 8, 30),
      );
    });

    test('unknown schedule keeps the 24 hour cadence', () {
      final from = DateTime(2026, 11, 5, 8, 0);
      expect(
        nextCronRunAt('something-else', from),
        DateTime(2026, 11, 6, 8, 0),
      );
    });
  });

  group('CronTask JSON', () {
    test('old tasks without a mode default to reminder', () {
      final task = CronTask.fromJson({
        'id': 'task_1',
        'title': 'Drink water',
        'prompt': 'Remind me to drink water',
        'type': 'oneShot',
        'nextRunAt': '2026-11-05T09:00:00.000',
        'isActive': true,
        'createdAt': '2026-11-05T08:00:00.000',
      });

      expect(task.mode, CronTaskMode.reminder);
      expect(task.recurringSchedule, isNull);
    });

    test('agent mode and daily schedule survive a round trip', () {
      final task = CronTask(
        id: 'task_2',
        title: 'Daily Tech News',
        prompt: 'Search today\'s technology news',
        type: CronTaskType.recurring,
        nextRunAt: DateTime(2026, 11, 6, 7, 0),
        recurringSchedule: 'daily@07:00',
        mode: CronTaskMode.agent,
        createdAt: DateTime(2026, 11, 5, 8, 0),
      );

      final restored = CronTask.fromJson(task.toJson());
      expect(restored.mode, CronTaskMode.agent);
      expect(restored.recurringSchedule, 'daily@07:00');
      expect(restored.nextRunAt, DateTime(2026, 11, 6, 7, 0));
      expect(restored.type, CronTaskType.recurring);
    });
  });

  group('describeCronSchedule', () {
    CronTask task(String? schedule) => CronTask(
          id: 'task_3',
          title: 'Test',
          prompt: 'Test',
          type: schedule == null ? CronTaskType.oneShot : CronTaskType.recurring,
          nextRunAt: DateTime(2026, 11, 5, 8, 0),
          recurringSchedule: schedule,
          createdAt: DateTime(2026, 11, 5, 8, 0),
        );

    test('formats the supported schedules', () {
      expect(describeCronSchedule(task(null)), 'One-shot');
      expect(describeCronSchedule(task('hourly')), 'Every hour');
      expect(describeCronSchedule(task('every_30m')), 'Every 30 minutes');
      expect(describeCronSchedule(task('daily@07:00')), 'Daily at 07:00');
      expect(describeCronSchedule(task('daily_7am')), 'Daily at 07:00');
    });
  });
}
