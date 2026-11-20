import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

/// Schedule block operations. Methods never throw; errors come back as
/// [Failure]. Days are plain calendar dates (sent as YYYY-MM-DD, no time
/// zone); times are 'HH:MM'.
abstract class ScheduleRepository {
  /// All (not deleted) blocks, `GET /schedule`.
  Future<Either<Failure, List<ScheduleBlock>>> getBlocks();

  /// Blocks scheduled on [day], `GET /schedule/day/{YYYY-MM-DD}`.
  Future<Either<Failure, List<ScheduleBlock>>> getBlocksForDay(DateTime day);

  /// `POST /schedule` (201). The body is complete: unrelated recurrence
  /// fields are sent as explicit null.
  Future<Either<Failure, ScheduleBlock>> createBlock({
    required String title,
    String? description,
    required ScheduleTime startTime,
    required ScheduleTime endTime,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  });

  /// `PATCH /schedule/{id}`; the body holds only the set/cleared fields and
  /// never `start_date`.
  Future<Either<Failure, ScheduleBlock>> updateBlock(int id, ScheduleChanges changes);

  /// `DELETE /schedule/{id}` (204, soft delete).
  Future<Either<Failure, void>> deleteBlock(int id);
}
