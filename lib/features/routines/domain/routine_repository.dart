import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/routines/domain/routine.dart';

/// Routine data operations. Methods never throw; errors come back as [Failure].
/// Days are plain calendar dates (sent as YYYY-MM-DD, no time zone).
abstract class RoutineRepository {
  /// Routines scheduled on [day], with completion and streaks.
  Future<Either<Failure, List<RoutineDayItem>>> getRoutinesForDay(DateTime day);

  /// Marks [routineId] completed on [day] (201 created or 200 already done).
  Future<Either<Failure, void>> markDone(int routineId, DateTime day);

  /// Removes the completion of [routineId] on [day] (204, idempotent).
  Future<Either<Failure, void>> undo(int routineId, DateTime day);
}
