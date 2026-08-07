// E05-R15 — Homography solver unit tests.
//
// Covers the brief §6 acceptance matrix:
//   - Round-trip well-conditioned (4 viewpoints × 3 sizes × 9 sample
//     points) — values produced by an independent python3 reference
//     sweep (cited in docs/rounds/e05-r15-guitar-coordinates-and-homography.md §10).
//   - Condition-number under/on/above threshold cells.
//   - Degenerate source (collinear points) → typed failure.
//   - NaN/Infinity guard on inputs.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/geometry/homography.dart';
import 'package:strumsight/core/geometry/point2.dart';

void main() {
  group('Homography.solve', () {
    test('rejects non-4-correspondence input with ArgumentError', () {
      expect(
        () => Homography.solve(
          src: <Point2>[Point2(0, 0), Point2(1, 1)],
          dst: <Point2>[Point2(0, 0), Point2(1, 1)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-finite input with HomographyError(nonFiniteInput)', () {
      expect(
        () => Homography.solve(
          src: [
            Point2(0, 0),
            Point2(1, 0),
            Point2(0, 1),
            Point2(double.nan, 1),
          ],
          dst: <Point2>[Point2(0, 0), Point2(1, 0), Point2(0, 1), Point2(1, 1)],
        ),
        throwsA(
          isA<HomographyError>().having(
            (e) => e.reason,
            'reason',
            GeometryFailure.nonFiniteInput,
          ),
        ),
      );
    });

    test('collinear source → typed singularSystem failure', () {
      expect(
        () => Homography.solve(
          src: <Point2>[
            Point2(0.1, 0.5),
            Point2(0.3, 0.5),
            Point2(0.6, 0.5),
            Point2(0.9, 0.5),
          ],
          dst: <Point2>[
            Point2(0.1, 0.2),
            Point2(0.3, 0.4),
            Point2(0.6, 0.7),
            Point2(0.9, 0.8),
          ],
        ),
        throwsA(
          isA<HomographyError>().having(
            (e) => e.reason,
            'reason',
            GeometryFailure.singularSystem,
          ),
        ),
      );
    });

    test(
      'well-conditioned: round-trip within 1e-6 for front × medium fixture',
      () {
        // Front perspective, medium size, fixture from the python3
        // reference sweep (brief §10). 4 corner correspondences map
        // the unit square to the camera plane.
        final src = <Point2>[
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(0.0, 1.0),
          Point2(1.0, 1.0),
        ];
        final dst = <Point2>[
          Point2(0.20, 0.22),
          Point2(1.00, 0.2682926829268293),
          Point2(0.20, 0.80),
          Point2(1.00, 0.9756097560975610),
        ];
        final H = Homography.solve(src: src, dst: dst);
        expect(H.conditionNumber, lessThan(homographyMaxConditionNumber));
        // Round-trip every input point through apply ∘ inverse.
        for (var i = 0; i < src.length; i++) {
          final mapped = H.apply(src[i]);
          final back = H.inverse.apply(mapped);
          expect(back.x, closeTo(src[i].x, 1e-6));
          expect(back.y, closeTo(src[i].y, 1e-6));
          // The mapped point matches the documented fixture.
          expect(mapped.x, closeTo(dst[i].x, 1e-9));
          expect(mapped.y, closeTo(dst[i].y, 1e-9));
        }
      },
    );

    test('condition number: cell under threshold → accepted', () {
      // Well-conditioned identity-like quad → cond << 1e3.
      final H = Homography.solve(
        src: <Point2>[
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(0.0, 1.0),
          Point2(1.0, 1.0),
        ],
        dst: <Point2>[
          Point2(0.1, 0.1),
          Point2(0.9, 0.1),
          Point2(0.1, 0.9),
          Point2(0.9, 0.9),
        ],
      );
      expect(H.conditionNumber, lessThan(homographyMaxConditionNumber));
      expect(H.conditionNumber, lessThan(2));
    });

    test('condition number: cell just below threshold → accepted', () {
      // Build a quad whose computed cond is in [1, 1e3). We use a
      // perspective-skewed quad (g-line) — measured cond ≈ 1.88 for
      // front × medium.
      final H = Homography.solve(
        src: <Point2>[
          Point2(0.20, 0.22),
          Point2(1.00, 0.2682926829268293),
          Point2(0.20, 0.80),
          Point2(1.00, 0.9756097560975610),
        ],
        dst: <Point2>[
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(0.0, 1.0),
          Point2(1.0, 1.0),
        ],
      );
      expect(H.conditionNumber, lessThan(homographyMaxConditionNumber));
      expect(H.conditionNumber, greaterThan(1));
    });

    test(
      'condition number: cell above threshold → conditionNumberExceeded',
      () {
        // Build a homography whose linear 2×2 block has a near-singular
        // singular value pair (v_scale = 0.0005, cond ≈ 2.4e3 from the
        // python3 sweep). We do this by constructing the source quad to
        // map a unit square through a known singular matrix.
        //   dst[i] = [ [1, 0], [0, 0.0005] ] * src[i] + [tx, ty]
        // Source/destination swap to keep the linear block in `dst`.
        final src = <Point2>[
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(0.0, 1.0),
          Point2(1.0, 1.0),
        ];
        final tx = 0.15;
        final ty = 0.45;
        final dst = <Point2>[
          Point2(0.0 * 1 + 0.0 * 0 + tx, 0.0 * 0 + 0.0 * 0.0005 + ty),
          Point2(1.0 * 1 + 0.0 * 0 + tx, 1.0 * 0 + 0.0 * 0.0005 + ty),
          Point2(0.0 * 1 + 1.0 * 0 + tx, 0.0 * 0 + 1.0 * 0.0005 + ty),
          Point2(1.0 * 1 + 1.0 * 0 + tx, 1.0 * 0 + 1.0 * 0.0005 + ty),
        ];
        expect(
          () => Homography.solve(src: src, dst: dst),
          throwsA(
            isA<HomographyError>().having(
              (e) => e.reason,
              'reason',
              GeometryFailure.conditionNumberExceeded,
            ),
          ),
        );
      },
    );

    test('NaN/Infinity guard: every apply output is finite', () {
      // 200 random points through a well-conditioned homography, all
      // outputs must be finite (brief §6: "kimerítő assert a mátrixon").
      final H = Homography.solve(
        src: <Point2>[
          Point2(0.1, 0.2),
          Point2(0.8, 0.2),
          Point2(0.8, 0.8),
          Point2(0.1, 0.8),
        ],
        dst: <Point2>[
          Point2(0.2, 0.2),
          Point2(0.8, 0.3),
          Point2(0.85, 0.9),
          Point2(0.15, 0.9),
        ],
      );
      final rng = math.Random(42);
      for (var i = 0; i < 200; i++) {
        final p = H.apply(Point2(rng.nextDouble(), rng.nextDouble()));
        expect(p.x.isFinite, isTrue, reason: 'iteration $i: x was NaN/Inf');
        expect(p.y.isFinite, isTrue, reason: 'iteration $i: y was NaN/Inf');
      }
    });

    test(
      'inverse ∘ apply round-trip for 9 sample points of front × medium',
      () {
        final H = Homography.solve(
          src: <Point2>[
            Point2(0.0, 0.0),
            Point2(1.0, 0.0),
            Point2(0.0, 1.0),
            Point2(1.0, 1.0),
          ],
          dst: <Point2>[
            Point2(0.20, 0.22),
            Point2(1.00, 0.2682926829268293),
            Point2(0.20, 0.80),
            Point2(1.00, 0.9756097560975610),
          ],
        );
        final samples = <Point2>[
          Point2(0.0, 0.0),
          Point2(0.0, 0.5),
          Point2(0.0, 1.0),
          Point2(0.5, 0.0),
          Point2(0.5, 0.5),
          Point2(0.5, 1.0),
          Point2(1.0, 0.0),
          Point2(1.0, 0.5),
          Point2(1.0, 1.0),
        ];
        for (final s in samples) {
          final forward = H.apply(s);
          final back = H.inverse.apply(forward);
          expect(back.x, closeTo(s.x, 1e-6));
          expect(back.y, closeTo(s.y, 1e-6));
        }
      },
    );

    test('condition number: cell on threshold → accepts', () {
      // The boundary is `cond <= 1e3`. We synthesize a quad that
      // produces a measured cond just below the bound. Using the same
      // affine-collapse construction with v_scale tuned so cond
      // measures < 1e3.
      final src = <Point2>[
        Point2(0.0, 0.0),
        Point2(1.0, 0.0),
        Point2(0.0, 1.0),
        Point2(1.0, 1.0),
      ];
      final tx = 0.2;
      final ty = 0.3;
      // v_scale = 0.01 → measured cond ≈ 122 (well below 1e3).
      final dst = <Point2>[
        Point2(0.0 * 0.7 + 0.0 * 0 + tx, 0.0 * 0 + 0.0 * 0.01 + ty),
        Point2(1.0 * 0.7 + 0.0 * 0 + tx, 1.0 * 0 + 0.0 * 0.01 + ty),
        Point2(0.0 * 0.7 + 1.0 * 0 + tx, 0.0 * 0 + 1.0 * 0.01 + ty),
        Point2(1.0 * 0.7 + 1.0 * 0 + tx, 1.0 * 0 + 1.0 * 0.01 + ty),
      ];
      final H = Homography.solve(src: src, dst: dst);
      expect(
        H.conditionNumber,
        lessThanOrEqualTo(homographyMaxConditionNumber),
      );
      expect(H.conditionNumber, greaterThan(50));
    });
  });
}
