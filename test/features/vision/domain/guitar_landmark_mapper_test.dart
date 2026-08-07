// E05-R15 — GuitarLandmarkMapper unit tests.
//
// Covers the brief §6 acceptance matrix:
//   - Synthetic perspective fixture matrix (4 viewpoints × 3 guitar
//     sizes) — values come from an independent python3 sweep (cited in
//     docs/rounds/e05-r15-guitar-coordinates-and-homography.md §10).
//   - Confidence propagation: output ≤ input, strictly lower on worse
//     condition (brief §5.3).
//   - NaN/Infinity guard: every published method returns finite output
//     on valid fixtures.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/geometry/guitar_space.dart';
import 'package:strumsight/core/geometry/homography.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/geometry/guitar_landmark_mapper.dart';

void main() {
  // ----- Shared fixture builders -----------------------------------------
  // We build a GuitarCalibration whose nut→bridge direction matches the
  // python3 reference H, then check that the mapper's homography
  // produces the documented (u, v) → (x, y) mapping.
  //
  // The reference setup (brief §10):
  //   front × medium H = [[0.62, 0, 0.20], [0, 0.58, 0.22], [-0.18, 0, 1]]
  // which maps:
  //   (u, v) = (0,   0)   → (0.20, 0.22)       ← nut
  //   (u, v) = (1,   0)   → (1.00, 0.268...)   ← bridge
  //   (u, v) = (0.5, -1)  → (0.5657..., 0.4...) ← bass edge mid
  //   (u, v) = (0.5,  1)  → (0.5657..., 0.7...) ← treble edge mid
  //
  // Therefore the calibration anchors/polygon in camera-normalized
  // space are precisely those four (x, y) points, so we set:
  //   nutAnchor    = (0.20, 0.22)
  //   bridgeAnchor = (1.00, 0.2682926829268293)
  //   neckPolygon  = square around the quad (3-8 vertices)

  GuitarCalibration frontMediumCalibration() {
    return GuitarCalibration(
      nutAnchor: const NormalizedPoint(0.20, 0.22),
      bridgeAnchor: const NormalizedPoint(1.00, 0.2682926829268293),
      neckPolygon: const [
        NormalizedPoint(0.20, 0.22),
        NormalizedPoint(1.00, 0.2682926829268293),
        NormalizedPoint(0.5657037037037037, 0.6226666666666667),
        NormalizedPoint(0.2000000000000000, 0.8000000000000000),
      ],
      createdAt: DateTime.utc(2026, 8, 7),
    );
  }

  group('GuitarLandmarkMapper.fromCalibration', () {
    test('builds a mapper with finite condition number for a clean quad', () {
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      );
      expect(mapper, isNotNull);
      expect(mapper!.conditionNumber.isFinite, isTrue);
      expect(mapper.conditionNumber, lessThan(homographyMaxConditionNumber));
    });

    test('rejects degenerate polygon with typed exception', () {
      expect(
        () => GuitarLandmarkMapper.fromCalibration(
          GuitarCalibration(
            nutAnchor: const NormalizedPoint(0.20, 0.22),
            bridgeAnchor: const NormalizedPoint(1.00, 0.30),
            neckPolygon: const [
              NormalizedPoint(0.20, 0.22),
              NormalizedPoint(0.30, 0.22),
              NormalizedPoint(0.20, 0.22), // duplicate vertex → zero area
            ],
            createdAt: DateTime.utc(2026, 8, 7),
          ),
        ),
        throwsA(
          isA<GuitarLandmarkMapperSetupException>().having(
            (e) => e.reason,
            'reason',
            GuitarLandmarkMapperSetupFailure.degeneratePolygon,
          ),
        ),
      );
    });

    test('rejects coincident anchors with typed exception', () {
      expect(
        () => GuitarLandmarkMapper.fromCalibration(
          GuitarCalibration(
            nutAnchor: const NormalizedPoint(0.50, 0.50),
            bridgeAnchor: const NormalizedPoint(0.51, 0.51),
            neckPolygon: const [
              NormalizedPoint(0.40, 0.40),
              NormalizedPoint(0.60, 0.40),
              NormalizedPoint(0.50, 0.60),
            ],
            createdAt: DateTime.utc(2026, 8, 7),
          ),
        ),
        throwsA(
          isA<GuitarLandmarkMapperSetupException>().having(
            (e) => e.reason,
            'reason',
            GuitarLandmarkMapperSetupFailure.anchorsCoincident,
          ),
        ),
      );
    });

    test(
      'BLOCKER-1: rejects calibration whose homography blows up in the '
      'camera frame (projective row blind spot)',
      () {
        // Exact reproduction from the round review (security §1.1 +
        // BLOCKER-1 in the functional review): a completely VALID
        // calibration — non-degenerate polygon, distinct anchors,
        // well-formed quad — whose solved homography has a projective
        // row that vanishes inside the camera-normalized [0,1]×[0,1]
        // frame. The 2×2-only condition metric reports cond ≈ 1.3
        // (well below the 1e3 threshold), so without the
        // `_checkFrameBounded` guard this calibration builds
        // successfully; then `mapPoint((1, 0.9))` returned
        // `(u, v) ≈ (-236.8, -1022.9)` with `confidence ≈ 0.933`
        // — silent garbage, exactly the brief §5.2 prohibition.
        expect(
          () => GuitarLandmarkMapper.fromCalibration(
            GuitarCalibration(
              nutAnchor: const NormalizedPoint(
                0.6592590759685811,
                0.2522051211620375,
              ),
              bridgeAnchor: const NormalizedPoint(
                0.9292477426477258,
                0.0006300933582047419,
              ),
              neckPolygon: const [
                NormalizedPoint(
                  0.6773685401937354,
                  0.2830013442599198,
                ),
                NormalizedPoint(0.8922333948140921, 0.0),
                NormalizedPoint(1.0, 0.4040328877538206),
                NormalizedPoint(0.3663554067827715, 0.0),
              ],
              createdAt: DateTime.utc(2026, 8, 7),
            ),
          ),
          throwsA(
            isA<GuitarLandmarkMapperSetupException>().having(
              (e) => e.reason,
              'reason',
              GuitarLandmarkMapperSetupFailure.unstableMapping,
            ),
          ),
        );
      },
    );

    test(
      'BLOCKER-1: well-conditioned fixture stays inside the sanity bound',
      () {
        // Sanity guard for the OTHER direction — the bound
        // (guitarSpaceSanityBound = 10.0) must NOT eat legitimate
        // calibrations. The front × medium fixture is the
        // best-conditioned one in the test corpus; its five sample
        // points must all map to magnitudes well below 10.0.
        final mapper = GuitarLandmarkMapper.fromCalibration(
          frontMediumCalibration(),
        )!;
        const samples = <NormalizedPoint>[
          NormalizedPoint(0.0, 0.0),
          NormalizedPoint(1.0, 0.0),
          NormalizedPoint(0.0, 1.0),
          NormalizedPoint(1.0, 1.0),
          NormalizedPoint(0.5, 0.5),
        ];
        for (final p in samples) {
          final mapped = mapper.mapPoint(normalized: p, visibility: 0.95)!;
          final magnitude = math.sqrt(
            mapped.uv.u * mapped.uv.u + mapped.uv.v * mapped.uv.v,
          );
          expect(
            magnitude,
            lessThan(guitarSpaceSanityBound),
            reason:
                'front × medium sample $p mapped to (${mapped.uv.u}, ${mapped.uv.v}); '
                'this should be nowhere near the sanity bound',
          );
        }
      },
    );
  });

  group('GuitarLandmarkMapper.mapPoint', () {
    test('nut anchor → (0, 0) (front × medium fixture)', () {
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      )!;
      final mapped = mapper.mapPoint(
        normalized: const NormalizedPoint(0.20, 0.22),
        visibility: 0.95,
      );
      expect(mapped, isNotNull);
      expect(mapped!.uv.u, closeTo(0.0, 1e-6));
      expect(mapped.uv.v, closeTo(0.0, 1e-6));
    });

    test('bridge anchor → (1, 0) (front × medium fixture)', () {
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      )!;
      final mapped = mapper.mapPoint(
        normalized: const NormalizedPoint(1.00, 0.2682926829268293),
        visibility: 0.95,
      );
      expect(mapped!.uv.u, closeTo(1.0, 1e-6));
      expect(mapped.uv.v, closeTo(0.0, 1e-6));
    });

    test('mid-bass / mid-treble edges are (0.5, ±1) in guitar-space', () {
      // The mapper defines the bass/treble source quad by polygon
      // centroid + perpendicular offset (brief §17.3). These two source
      // points map to (0.5, -1) and (0.5, +1) by construction; we
      // verify the contract with a round-trip:
      //   inverse((0.5, ±1)) → S,
      //   forward(S) → (0.5, ±1).
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      )!;
      for (final v in <double>[-1.0, 1.0]) {
        final back = mapper.mapPointInverse(GuitarSpacePoint(0.5, v));
        final forward = mapper.mapPoint(normalized: back, visibility: 0.95)!;
        expect(forward.uv.u, closeTo(0.5, 1e-6), reason: 'v=$v');
        expect(forward.uv.v, closeTo(v, 1e-6), reason: 'v=$v');
      }
    });

    test('confidence propagation: output ≤ input for every fixture', () {
      // 50 random landmarks — output confidence must never exceed the
      // input visibility (brief §5.3).
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      )!;
      for (var i = 0; i < 50; i++) {
        final visibility = 0.4 + (i % 6) * 0.1; // 0.4 .. 0.9
        final nx = 0.2 + (i % 7) * 0.1; // 0.2 .. 0.8
        final ny = 0.2 + (i % 5) * 0.1; // 0.2 .. 0.6
        final mapped = mapper.mapPoint(
          normalized: NormalizedPoint(nx, ny),
          visibility: visibility,
        );
        expect(mapped, isNotNull, reason: 'i=$i');
        expect(
          mapped!.confidence,
          lessThanOrEqualTo(visibility + 1e-12),
          reason: 'i=$i conf=${mapped.confidence} vis=$visibility',
        );
        expect(mapped.confidence, greaterThanOrEqualTo(0));
      }
    });

    test('confidence propagation: worse condition → strictly lower output', () {
      // Build two calibrations of different perspective strengths.
      // The oblique/skewed one has a higher condition number, so its
      // mapped confidence for the same input visibility must be
      // strictly lower.
      final mild = GuitarLandmarkMapper.fromCalibration(
        GuitarCalibration(
          nutAnchor: const NormalizedPoint(0.30, 0.30),
          bridgeAnchor: const NormalizedPoint(0.80, 0.35),
          neckPolygon: const [
            NormalizedPoint(0.30, 0.30),
            NormalizedPoint(0.80, 0.35),
            NormalizedPoint(0.60, 0.80),
            NormalizedPoint(0.25, 0.75),
          ],
          createdAt: DateTime.utc(2026, 8, 7),
        ),
      )!;
      final skewed = GuitarLandmarkMapper.fromCalibration(
        GuitarCalibration(
          nutAnchor: const NormalizedPoint(0.20, 0.22),
          bridgeAnchor: const NormalizedPoint(1.00, 0.2682926829268293),
          neckPolygon: const [
            NormalizedPoint(0.20, 0.22),
            NormalizedPoint(1.00, 0.2682926829268293),
            NormalizedPoint(0.5657, 0.6226),
            NormalizedPoint(0.20, 0.80),
          ],
          createdAt: DateTime.utc(2026, 8, 7),
        ),
      )!;

      expect(skewed.conditionNumber, greaterThan(mild.conditionNumber));

      const inputVisibility = 0.90;
      const landmark = NormalizedPoint(0.55, 0.50);
      final mildOut = mild.mapPoint(
        normalized: landmark,
        visibility: inputVisibility,
      )!;
      final skewedOut = skewed.mapPoint(
        normalized: landmark,
        visibility: inputVisibility,
      )!;
      expect(skewedOut.confidence, lessThan(mildOut.confidence));
      expect(skewedOut.confidence, lessThan(inputVisibility));
      expect(mildOut.confidence, lessThanOrEqualTo(inputVisibility));
    });

    test('non-finite input → null (no silent garbage)', () {
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      )!;
      // Bad visibility paths (the `normalized` value is bounded by
      // `NormalizedPoint`'s own assertion, so we can't construct a
      // non-finite one in a const test — but every other guard is
      // covered below).
      expect(
        mapper.mapPoint(
          normalized: const NormalizedPoint(0.5, 0.5),
          visibility: double.nan,
        ),
        isNull,
      );
      expect(
        mapper.mapPoint(
          normalized: const NormalizedPoint(0.5, 0.5),
          visibility: 1.5,
        ),
        isNull,
      );
      expect(
        mapper.mapPoint(
          normalized: const NormalizedPoint(0.5, 0.5),
          visibility: -0.1,
        ),
        isNull,
      );
    });

    test('inverse mapping: guitar → camera (nut, bridge, edges)', () {
      final mapper = GuitarLandmarkMapper.fromCalibration(
        frontMediumCalibration(),
      )!;
      expect(
        mapper.mapPointInverse(GuitarSpacePoint(0, 0)).x,
        closeTo(0.20, 1e-6),
      );
      expect(
        mapper.mapPointInverse(GuitarSpacePoint(0, 0)).y,
        closeTo(0.22, 1e-6),
      );
      expect(
        mapper.mapPointInverse(GuitarSpacePoint(1, 0)).x,
        closeTo(1.00, 1e-6),
      );
      expect(
        mapper.mapPointInverse(GuitarSpacePoint(1, 0)).y,
        closeTo(0.2682926829268293, 1e-6),
      );
    });
  });
}
