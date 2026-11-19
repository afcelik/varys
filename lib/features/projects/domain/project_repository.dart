import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';

/// Project operations. Methods never throw; errors come back as [Failure].
/// Activating beyond the limit (create or update) returns
/// [ActiveProjectLimitFailure]. Dates are plain `YYYY-MM-DD` days.
abstract class ProjectRepository {
  /// `GET /projects`, optionally filtered by [status] (`?status=`).
  /// Without [status] every (not deleted) project is returned.
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status});

  /// `GET /projects/limits`: active project limit and current usage.
  Future<Either<Failure, ProjectLimits>> getLimits();

  /// `POST /projects` (201).
  Future<Either<Failure, Project>> createProject(ProjectDraft draft);

  /// `PATCH /projects/{id}`; the body holds only the set/cleared fields.
  Future<Either<Failure, Project>> updateProject(int id, ProjectChanges changes);

  /// `DELETE /projects/{id}` (204, soft delete; linked tasks are unlinked).
  Future<Either<Failure, void>> deleteProject(int id);
}
