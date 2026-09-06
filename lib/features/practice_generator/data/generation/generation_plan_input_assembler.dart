/// A Setup-varázsló kérése → `GenerationPlanInput` (2026-09-05).
///
/// Ez a `generationPlanInputBuilderProvider` hiányzó darabja. A seam
/// docstringje eddig azt mondta: „the concrete production builder is a later
/// round's composition" — emiatt dobott élesben, és emiatt maradt a
/// gyakorlástervező generálási ága bekötetlen.
///
/// **Nem ír generálási logikát.** Minden lépést a MÁR MEGLÉVŐ szolgáltatások
/// végzik: a napi keretet a `TimeBudgetAllocator`, a heti beosztást a
/// `WeeklyScheduler`, az érvényesítést a `PlanValidationContext`. Ez a modul
/// a négy meglévő darab összekötése.
///
/// ## Két dokumentált leképezés
///
/// **A jelölt egyetlen terhelési szintje a hat dimenzió MAXIMUMA.** A
/// `ScheduleCandidate` egyetlen `LoadLevel`-t visz, az `ExerciseCandidate`
/// viszont hatot. Az átlagolás elrejtené a szélsőértéket — egy egyébként
/// könnyű gyakorlat, aminek a fogó keze `high` (pl. az F barré), átlagban
/// `medium`-nak látszana, és a beosztó könnyebbnek hinné, mint amilyen. A
/// maximum a konzervatív irány: a gyakorlat annyira terhelő, amennyire a
/// legnehezebb dimenziója.
///
/// **Minden jelölt `newMaterial`.** A „már tanult" besorolás a tanulói
/// bizonyíték-pipeline-tól függ, az viszont aszinkron olvasás, míg ez a seam
/// SZINKRON (`GenerationPlanInput Function(request)`). A `review` besorolás
/// tehát nem azért marad el, mert nincs rá adat, hanem mert ezen a
/// felületen nem érhető el. Következménye MÉRHETŐ: a beosztó ismétlés-aránya
/// az első generáláson nem tud érvényesülni. Ez a seam bővítésének külön
/// köre — a szerződés aszinkronná tétele.
library;

import '../../application/service/generation_orchestrator.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/practice_catalog_snapshot.dart';
import '../../domain/model/practice_generation_request.dart';
import '../../domain/model/schedule_decision.dart';
import '../../domain/model/time_budget.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/scheduling_policy.dart';
import '../../domain/service/plan_validator.dart' show PlanValidationContext;
import '../../domain/service/time_budget_allocator.dart';
import '../../domain/service/weekly_scheduler.dart';

/// A hat dimenzió közül a legterhelőbb. Lásd a modul docstringjét.
LoadLevel dominantLoadLevel(ExerciseLoadProfile profile) {
  var worst = LoadLevel.low;
  for (final level in <LoadLevel>[
    profile.cognitive,
    profile.frettingHand,
    profile.pickingHand,
    profile.repetition,
    profile.novelty,
    profile.concentration,
  ]) {
    if (level.index > worst.index) worst = level;
  }
  return worst;
}

/// A tanuló céljaihoz illeszkedő jelölt elsődleges fókuszt kap.
///
/// Az illesztés a jelölt `skillTargets`-e és a cél `skillIds`-e között megy —
/// NÉV szerint sosem. A cél nélküli generálás minden jelöltet `supporting`
/// szintre tesz: ilyenkor nincs mihez viszonyítani, és egy önkényesen
/// kiemelt „elsődleges" fókusz azt állítaná, hogy a rendszer tudja, mi a
/// fontos.
CandidateFocus focusFor(
  ExerciseCandidate candidate,
  PracticeGenerationRequest request,
) {
  if (request.goals.isEmpty) return CandidateFocus.supporting;
  final goalSkills = <String>{
    for (final goal in request.goals) ...goal.skillIds,
  };
  if (goalSkills.isEmpty) return CandidateFocus.supporting;
  final overlap = candidate.skillTargets.any(goalSkills.contains);
  return overlap ? CandidateFocus.primaryFocus : CandidateFocus.supporting;
}

/// Egy katalógus-jelölt beosztható alakja.
ScheduleCandidate scheduleCandidateFor(
  ExerciseCandidate candidate,
  PracticeGenerationRequest request,
) => ScheduleCandidate(
  // Ugyanaz az azonosító-alak, amit a `PracticeCatalogSnapshot` az
  // egyediség ellenőrzésére használ — így a beosztás és a katalógus
  // ugyanarra a kulcsra hivatkozik.
  identity: '${candidate.source.code}:${candidate.exerciseId}',
  focus: focusFor(candidate, request),
  materialKind: CandidateMaterialKind.newMaterial,
  loadLevel: dominantLoadLevel(candidate.loadProfile),
  duration: candidate.supportedDurations.minimum,
  skillTargets: candidate.skillTargets,
);

/// Összeállítja a generálás bemenetét egy befejezett Setup-kérésből.
final class GenerationPlanInputAssembler {
  const GenerationPlanInputAssembler({
    required this.catalog,
    required this.today,
    required this.generateId,
    this.allocator = const TimeBudgetAllocator(),
    this.scheduler = const WeeklyScheduler(),
  });

  final PracticeCatalogSnapshot catalog;
  final LocalDate Function() today;
  final String Function() generateId;
  final TimeBudgetAllocator allocator;
  final WeeklyScheduler scheduler;

  GenerationPlanInput call(PracticeGenerationRequest request) {
    final planId = PlanId.generate(generateId);
    final initialRevisionId = RevisionId.generate(generateId);

    // A napi keretet a MEGLÉVŐ allokátor adja. Az elérhetetlen napok
    // kimaradnak — az allokátor rájuk hibát dobna, és egy nulla perces
    // keret azt állítaná, hogy a nap elérhető, csak nincs rá idő.
    final dayBudgets = <LocalDate, TimeBudget>{};
    final restDays = <LocalDate>[];
    for (final day in request.availability.days) {
      if (day.status == AvailabilityStatus.unavailable) {
        restDays.add(day.date);
        continue;
      }
      dayBudgets[day.date] = allocator
          .allocate(
            availability: day,
            fromRevisionId: initialRevisionId,
            toRevisionId: initialRevisionId,
          )
          .budget;
    }

    final schedule = scheduler.schedule(
      WeeklyScheduleRequest(
        availability: request.availability,
        dayBudgets: dayBudgets,
        candidates: <ScheduleCandidate>[
          for (final candidate in catalog.candidates)
            scheduleCandidateFor(candidate, request),
        ],
        today: today(),
        restDays: restDays,
      ),
    );

    return GenerationPlanInput(
      request: request,
      schedule: schedule,
      validationContext: PlanValidationContext(
        catalog: catalog,
        availability: request.availability,
        // A javítási revízió a hívóé — az érvényesítő sosem gyárt
        // azonosítót magának (se óra, se véletlen).
        repairRevisionId: RevisionId.generate(generateId),
      ),
      planId: planId,
      initialRevisionId: initialRevisionId,
    );
  }
}
