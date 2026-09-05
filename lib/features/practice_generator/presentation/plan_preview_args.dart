/// Az előnézeti képernyő útvonal-argumentuma (2026-09-05).
///
/// A `PlanPreviewScreen` egy kész `PlanPreviewController`-t vár, azt viszont
/// két adatból kell felépíteni: a megjelenítendő tervből és az érvényesítési
/// kontextusból. A kettő EGYÜTT keletkezik a generálás végén, ezért egy
/// argumentum-típus viszi őket — nem két külön `extra`, amiből az egyik
/// lemaradhatna.
///
/// A `practice_route_args.dart` precedensét követi.
library;

import '../domain/model/adaptive_practice_plan.dart';
import '../domain/service/plan_validator.dart' show PlanValidationContext;

final class PracticePlanPreviewArgs {
  const PracticePlanPreviewArgs({
    required this.plan,
    required this.validationContext,
  });

  final AdaptivePracticePlan plan;
  final PlanValidationContext validationContext;
}
