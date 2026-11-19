import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/projects/domain/project.dart';

/// Project read operations. Methods never throw; errors come back as [Failure].
/// Create/update/delete come in a later step.
abstract class ProjectRepository {
  /// `GET /projects`, optionally filtered by [status] (`?status=`).
  /// Deleted projects are never returned.
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status});

  /// `GET /projects/limits`: active project limit and current usage.
  Future<Either<Failure, ProjectLimits>> getLimits();
}
