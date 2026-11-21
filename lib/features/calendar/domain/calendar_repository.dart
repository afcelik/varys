import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';

/// Month calendar summary. Methods never throw; errors come back as
/// [Failure].
abstract class CalendarRepository {
  /// Per-day counts of [month] in [year], `GET /calendar/month?year=&month=`.
  Future<Either<Failure, CalendarMonth>> getMonth(int year, int month);
}
