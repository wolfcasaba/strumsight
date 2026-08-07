// E05-R15 — Polygon predicate unit tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/geometry/point2.dart';
import 'package:strumsight/core/geometry/polygon2.dart';

void main() {
  group('Polygon2.validate', () {
    test('tooFewVertices for 0/1/2 vertex lists', () {
      expect(Polygon2.validate(<Point2>[]).isValid, isFalse);
      expect(Polygon2.validate(<Point2>[Point2(0, 0)]).isValid, isFalse);
      expect(
        Polygon2.validate(<Point2>[Point2(0, 0), Point2(1, 0)]).isValid,
        isFalse,
      );
    });

    test('zeroSignedArea for collinear points', () {
      expect(
        Polygon2.validate(<Point2>[
          Point2(0.0, 0.5),
          Point2(0.3, 0.5),
          Point2(0.6, 0.5),
          Point2(0.9, 0.5),
        ]).reason,
        PolygonDegenerateReason.zeroSignedArea,
      );
    });

    test('valid for a convex CCW quad', () {
      expect(
        Polygon2.validate(<Point2>[
          Point2(0.1, 0.1),
          Point2(0.9, 0.1),
          Point2(0.9, 0.9),
          Point2(0.1, 0.9),
        ]).isValid,
        isTrue,
      );
    });
  });

  group('Polygon2.signedArea', () {
    test('positive for CCW, negative for CW, zero for degenerate', () {
      final ccw = [
        Point2(0.0, 0.0),
        Point2(1.0, 0.0),
        Point2(1.0, 1.0),
        Point2(0.0, 1.0),
      ];
      final cw = [
        Point2(0.0, 0.0),
        Point2(0.0, 1.0),
        Point2(1.0, 1.0),
        Point2(1.0, 0.0),
      ];
      expect(Polygon2.signedArea(ccw), greaterThan(0));
      expect(Polygon2.signedArea(cw), lessThan(0));
      expect(Polygon2.signedArea(<Point2>[Point2(0, 0), Point2(1, 0)]), 0);
    });
  });

  group('Polygon2.orientation', () {
    test('counterClockwise for CCW quad', () {
      expect(
        Polygon2.orientation(<Point2>[
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(1.0, 1.0),
          Point2(0.0, 1.0),
        ]),
        PolygonOrientation.counterClockwise,
      );
    });

    test('clockwise for CW quad', () {
      expect(
        Polygon2.orientation(<Point2>[
          Point2(0.0, 0.0),
          Point2(0.0, 1.0),
          Point2(1.0, 1.0),
          Point2(1.0, 0.0),
        ]),
        PolygonOrientation.clockwise,
      );
    });

    test('null for degenerate polygons', () {
      expect(
        Polygon2.orientation(<Point2>[Point2(0, 0), Point2(1, 0)]),
        isNull,
      );
      expect(
        Polygon2.orientation(<Point2>[
          Point2(0.0, 0.5),
          Point2(0.3, 0.5),
          Point2(0.6, 0.5),
          Point2(0.9, 0.5),
        ]),
        isNull,
      );
    });
  });

  group('Polygon2.isConvex', () {
    test('convex quad → true', () {
      expect(
        Polygon2.isConvex(<Point2>[
          Point2(0.1, 0.1),
          Point2(0.9, 0.1),
          Point2(0.9, 0.9),
          Point2(0.1, 0.9),
        ]),
        isTrue,
      );
    });

    test('concave quad (chevron) → false', () {
      expect(
        Polygon2.isConvex(<Point2>[
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(0.5, 0.5),
          Point2(1.0, 1.0),
          Point2(0.0, 1.0),
        ]),
        isFalse,
      );
    });

    test(
      'degenerate polygon → false (paired with validate for explicitness)',
      () {
        final result = Polygon2.isConvex(<Point2>[
          Point2(0.0, 0.5),
          Point2(0.3, 0.5),
          Point2(0.6, 0.5),
        ]);
        expect(result, isFalse);
        expect(
          Polygon2.validate(<Point2>[
            Point2(0.0, 0.5),
            Point2(0.3, 0.5),
            Point2(0.6, 0.5),
          ]).isValid,
          isFalse,
        );
      },
    );
  });

  group('Polygon2.contains', () {
    final square = [
      Point2(0.0, 0.0),
      Point2(1.0, 0.0),
      Point2(1.0, 1.0),
      Point2(0.0, 1.0),
    ];

    test('interior point → true', () {
      expect(Polygon2.contains(square, Point2(0.5, 0.5)), isTrue);
    });

    test('outside point → false', () {
      expect(Polygon2.contains(square, Point2(1.5, 0.5)), isFalse);
    });

    test('degenerate polygon → false', () {
      expect(
        Polygon2.contains(<Point2>[
          Point2(0, 0),
          Point2(1, 0),
        ], Point2(0.5, 0.0)),
        isFalse,
      );
    });

    test('interior point → true for a 90°-rotated square (rhombus)', () {
      // A rhombus centered on the origin with vertical axis
      // `(0,-1),(1,0),(0,1),(-1,0)` — none of its edges is axis-aligned,
      // so every edge has `b.y < a.y` (or `> a.y` for the other half).
      // The pre-fix `.abs()` in the ray-casting denominator flipped the
      // sign on every edge and silently produced `false` for the
      // trivially-inside origin. Regression guard for MAJOR-1.
      final rhombus = <Point2>[
        Point2(0, -1),
        Point2(1, 0),
        Point2(0, 1),
        Point2(-1, 0),
      ];
      expect(Polygon2.contains(rhombus, Point2(0, 0)), isTrue);
      // And a point outside the rhombus still returns false.
      expect(Polygon2.contains(rhombus, Point2(1.5, 1.5)), isFalse);
    });

    test('skewed guitar-neck quad → true for interior point', () {
      // Real-world-shape non-axis-aligned quad (similar to a neck
      // calibration's convex hull). The interior midpoint must be true;
      // a point clearly outside must be false. Both directions guard
      // against the sign-flip reappearing.
      final neck = <Point2>[
        Point2(0.1, 0.1),
        Point2(0.9, 0.3),
        Point2(0.8, 0.9),
        Point2(0.2, 0.7),
      ];
      expect(Polygon2.contains(neck, Point2(0.5, 0.5)), isTrue);
      expect(Polygon2.contains(neck, Point2(0.0, 0.5)), isFalse);
    });
  });
}
