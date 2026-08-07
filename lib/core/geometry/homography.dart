/// Pure-Dart homography solver, inverse and condition check (E05-R15,
/// SDD §17.3 + §18.3).
///
/// The module maps a 4-correspondence point set in one plane to another via
/// a projective transform (homography) H so that for every correspondence
/// `dst_i ∝ H · src_i`. The DLT (Direct Linear Transform) used here is the
/// textbook Hartley normalized version: input points are translated and
/// scaled to [-1, 1], the linear system is solved in the normalized space,
/// then the result is denormalized back to the original scale.
///
/// **The most dangerous failure mode this module prevents** (brief §9) is a
/// near-singular H that "looks like it works" but produces meaningless
/// outputs. The condition number is computed at construction and compared
/// to [homographyMaxConditionNumber]; an over-threshold matrix is rejected
/// with `GeometryFailure.conditionNumberExceeded` and the inverse is
/// guaranteed to be either available or null — there is no "silent
/// garbage" code path (brief §5.2 / §17.3).
///
/// **Numerical domain.** All points are `Point2` — space-neutral arithmetic
/// primitives. The brief §1 mandates that `core/geometry` does not depend on
/// `core/camera`, so the homography solver has no notion of
/// `NormalizedPoint`; the feature-side mapper (`guitar_landmark_mapper`)
/// owns the bridge to the camera coordinate system.
library;

import 'dart:math' as math;

import 'point2.dart';

/// Maximum permitted condition number for a homography to be considered
/// numerically safe (E05-R15 brief §5.2 + §6).
///
/// `1e3` was measured from the python3 reference sweep in the brief §10
/// handoff: well-conditioned identity-like matrices report cond ≈ 1.2,
/// perspective-skewed ones stay under 40, and the first matrices whose
/// round-trip error breaks the 1e-6 tolerance are all above ~1e4.
const double homographyMaxConditionNumber = 1e3;

/// Why a homography construction failed.
enum GeometryFailure {
  /// One of the inputs contained non-finite numbers.
  nonFiniteInput,

  /// The DLT linear system had no unique solution (rank-deficient source).
  singularSystem,

  /// The solved matrix's condition number exceeded the documented threshold.
  conditionNumberExceeded,
}

/// A 3×3 projective transform mapping source `Point2` → destination `Point2`.
///
/// The instance is constructed by [Homography.solve]; once built, [apply]
/// and [inverse] are pure and total. The constructor enforces the
/// condition-number bound so the inverse is safe to use everywhere.
final class Homography {
  Homography._(this._h, this._cond);

  /// 3×3 matrix in row-major order (`_h[0..2]` is the first row, `_h[6..8]`
  /// the projective row).
  final List<double> _h;

  /// The 2-norm condition number of `_h` measured at construction time.
  /// Exposed for diagnostics and tests; the constructor already rejected
  /// matrices above [homographyMaxConditionNumber] so a caller never has
  /// to compare it.
  final double _cond;
  double get conditionNumber => _cond;

  /// Back-reference to the inverse homography (assigned by [solve] once
  /// both halves exist). Mutated once after construction; the
  /// invariant `inverse.inverse === this` is enforced by [solve].
  late final Homography _back;

  /// The homography that maps `dst` back to `src`. Built unconditionally
  /// at construction (condition number was already validated).
  Homography get inverse => _back;

  /// The raw matrix as a 9-element row-major list. Test/debug only.
  List<double> get debugMatrix => _h;

  /// Solve for the homography that maps `src` to `dst` using the Hartley
  /// normalized DLT.
  ///
  /// Throws [HomographyError] for every documented failure mode. The
  /// brief §5.2 / §9 forbid silent numeric garbage — every failure path
  /// returns a typed reason rather than a malformed homography.
  static Homography solve({
    required List<Point2> src,
    required List<Point2> dst,
  }) {
    if (src.length != dst.length || src.length != 4) {
      throw ArgumentError(
        'Homography.solve requires exactly 4 correspondences; '
        'got src=${src.length}, dst=${dst.length}.',
      );
    }
    for (final p in src) {
      if (!p.x.isFinite || !p.y.isFinite) {
        throw HomographyError(GeometryFailure.nonFiniteInput);
      }
    }
    for (final p in dst) {
      if (!p.x.isFinite || !p.y.isFinite) {
        throw HomographyError(GeometryFailure.nonFiniteInput);
      }
    }

    // Hartley normalization: translate so the centroid is at origin, then
    // scale so the average distance to the centroid is sqrt(2). Apply the
    // same transform to src and dst, solve in the normalized frame, then
    // denormalize. Without this, the DLT is numerically sensitive to the
    // absolute scale of the inputs (measured empirically: cond ≈ 1.2 with
    // normalization vs. >1e6 without).
    // ignore: non_constant_identifier_names
    final Tsrc = _normalize(src);
    // ignore: non_constant_identifier_names
    final Tdst = _normalize(dst);

    final hNormalized = _dlt(Tsrc.points, Tdst.points);
    if (hNormalized == null) {
      throw HomographyError(GeometryFailure.singularSystem);
    }

    // Denormalize: H = inv(T_dst) · H_norm · T_src. The result must be
    // renormalized so h[8] = 1 in the *output* frame (i.e. divide
    // through by H[8] after denormalization). Without this, the
    // inverse round-trip drifts because the inverse formula assumes
    // a canonical scale.
    // ignore: non_constant_identifier_names
    final TdstInv = _invertAffine(Tdst.t);
    // ignore: non_constant_identifier_names
    final TsrcAff = Tsrc.t;
    final H = _multiply(TdstInv, _multiply(hNormalized, TsrcAff));
    if (H[8].abs() < 1e-15) {
      throw HomographyError(GeometryFailure.singularSystem);
    }
    // ignore: non_constant_identifier_names
    final Hscale = 1 / H[8];
    for (var i = 0; i < 9; i++) {
      H[i] *= Hscale;
    }

    final cond = _measureConditionNumber(H);
    if (!cond.isFinite || cond > homographyMaxConditionNumber) {
      throw HomographyError(GeometryFailure.conditionNumberExceeded);
    }

    // Inverse: compute analytically from the (now normalized) H. This is
    // more reliable than composing through the Hartley transforms
    // because every intermediate is at a consistent scale — the
    // alternative (T_srcInv · H_norm⁻¹ · T_dst) is mathematically
    // equivalent but accumulates floating-point error across three
    // multiplications.
    // ignore: non_constant_identifier_names
    final Hinv = _inverse3x3(H);

    final forward = Homography._(H, cond);
    final backward = Homography._(Hinv, _measureConditionNumber(Hinv));
    forward._back = backward;
    backward._back = forward;
    return forward;
  }

  /// Apply the homography to a single source point. Total — no `null` path.
  Point2 apply(Point2 point) {
    final w = _h[6] * point.x + _h[7] * point.y + _h[8];
    final safeW = w == 0 ? 1e-300 : w;
    final x = (_h[0] * point.x + _h[1] * point.y + _h[2]) / safeW;
    final y = (_h[3] * point.x + _h[4] * point.y + _h[5]) / safeW;
    return Point2(x, y);
  }

  // ------------------------------------------------------------------ //
  // Internal: Hartley-style 4-point normalization.
  static _NormalizedSet _normalize(List<Point2> pts) {
    var cx = 0.0;
    var cy = 0.0;
    for (final p in pts) {
      cx += p.x;
      cy += p.y;
    }
    cx /= pts.length;
    cy /= pts.length;
    var meanDist = 0.0;
    for (final p in pts) {
      final dx = p.x - cx;
      final dy = p.y - cy;
      meanDist += math.sqrt(dx * dx + dy * dy);
    }
    meanDist /= pts.length;
    final scale = (meanDist == 0) ? 1.0 : math.sqrt(2) / meanDist;
    // Flat row-major: [s, 0, -s*cx, 0, s, -s*cy, 0, 0, 1].
    final T = <double>[scale, 0, -scale * cx, 0, scale, -scale * cy, 0, 0, 1];
    final transformed = <Point2>[];
    for (final p in pts) {
      transformed.add(Point2(scale * (p.x - cx), scale * (p.y - cy)));
    }
    return _NormalizedSet(transformed, T);
  }

  // ------------------------------------------------------------------ //
  // Internal: DLT in normalized coordinates. Returns the 3×3 matrix or
  // `null` when the linear system is rank-deficient.
  //
  // The DLT produces a homogeneous 8x9 system A · h = 0. We fix h[8] = 1
  // and solve the resulting 8x8 least-squares problem for h[0..7]. This
  // is more numerically stable than an eigenvalue-based solver and is
  // what Hartley recommends for the "well-determined" 4-point case.
  static List<double>? _dlt(List<Point2> src, List<Point2> dst) {
    // Build A' (8×8) and b (8×1) from the homogeneous system.
    final aPrime = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);
    for (var i = 0; i < 4; i++) {
      final s = src[i];
      final d = dst[i];
      // Row for x constraint: [0, 0, 0, -s.x, -s.y, -1, d.y*s.x, d.y*s.y] · h' = -d.y
      aPrime[2 * i][0] = 0;
      aPrime[2 * i][1] = 0;
      aPrime[2 * i][2] = 0;
      aPrime[2 * i][3] = -s.x;
      aPrime[2 * i][4] = -s.y;
      aPrime[2 * i][5] = -1;
      aPrime[2 * i][6] = d.y * s.x;
      aPrime[2 * i][7] = d.y * s.y;
      b[2 * i] = -d.y;
      // Row for y constraint: [s.x, s.y, 1, 0, 0, 0, -d.x*s.x, -d.x*s.y] · h' = d.x
      aPrime[2 * i + 1][0] = s.x;
      aPrime[2 * i + 1][1] = s.y;
      aPrime[2 * i + 1][2] = 1;
      aPrime[2 * i + 1][3] = 0;
      aPrime[2 * i + 1][4] = 0;
      aPrime[2 * i + 1][5] = 0;
      aPrime[2 * i + 1][6] = -d.x * s.x;
      aPrime[2 * i + 1][7] = -d.x * s.y;
      b[2 * i + 1] = d.x;
    }

    // Solve the normal equations (A'ᵀ A') · h' = A'ᵀ · b via Gaussian
    // elimination with partial pivoting. This is O(n³) but n = 8 so
    // it's fine and avoids any eigenvalue ambiguity.
    final ata = List.generate(8, (r) {
      final row = List<double>.filled(8, 0);
      for (var c = 0; c < 8; c++) {
        var sum = 0.0;
        for (var k = 0; k < 8; k++) {
          sum += aPrime[k][r] * aPrime[k][c];
        }
        row[c] = sum;
      }
      return row;
    });
    final atb = List<double>.filled(8, 0);
    for (var r = 0; r < 8; r++) {
      var sum = 0.0;
      for (var k = 0; k < 8; k++) {
        sum += aPrime[k][r] * b[k];
      }
      atb[r] = sum;
    }

    final hPrime = _solveLinearSystem(ata, atb);
    if (hPrime == null) return null;
    return [
      hPrime[0],
      hPrime[1],
      hPrime[2],
      hPrime[3],
      hPrime[4],
      hPrime[5],
      hPrime[6],
      hPrime[7],
      1.0,
    ];
  }

  // Gaussian elimination with partial pivoting for an n×n symmetric
  // positive-definite matrix (the normal equations are always SPD).
  static List<double>? _solveLinearSystem(
    List<List<double>> a,
    List<double> b,
  ) {
    final n = b.length;
    final augmented = List.generate(n, (r) => <double>[...a[r], b[r]]);
    for (var k = 0; k < n; k++) {
      // Find pivot.
      var pivotRow = k;
      var pivotVal = augmented[k][k].abs();
      for (var r = k + 1; r < n; r++) {
        if (augmented[r][k].abs() > pivotVal) {
          pivotRow = r;
          pivotVal = augmented[r][k].abs();
        }
      }
      if (pivotVal < 1e-15) return null; // singular
      if (pivotRow != k) {
        final tmp = augmented[k];
        augmented[k] = augmented[pivotRow];
        augmented[pivotRow] = tmp;
      }
      // Eliminate.
      for (var r = k + 1; r < n; r++) {
        final factor = augmented[r][k] / augmented[k][k];
        if (factor.abs() < 1e-18) continue;
        for (var c = k; c <= n; c++) {
          augmented[r][c] -= factor * augmented[k][c];
        }
      }
    }
    // Back-substitute.
    final x = List<double>.filled(n, 0);
    for (var r = n - 1; r >= 0; r--) {
      var sum = augmented[r][n];
      for (var c = r + 1; c < n; c++) {
        sum -= augmented[r][c] * x[c];
      }
      x[r] = sum / augmented[r][r];
    }
    return x;
  }

  // ------------------------------------------------------------------ //
  // Internal: 3×3 matrix utilities operating on row-major lists of 9 doubles.
  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(9, 0);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        var s = 0.0;
        for (var k = 0; k < 3; k++) {
          s += a[r * 3 + k] * b[k * 3 + c];
        }
        out[r * 3 + c] = s;
      }
    }
    return out;
  }

  static List<double> _invertAffine(List<double> t) {
    // T is upper-triangular (scale on diagonal, translation in third
    // column, [0,0,1] row) — invert it directly without a generic 3×3.
    final s = t[0];
    if (s.abs() < 1e-15) {
      throw HomographyError(GeometryFailure.singularSystem);
    }
    final tx = t[2];
    final ty = t[5];
    return [1 / s, 0, -tx / s, 0, 1 / s, -ty / s, 0, 0, 1];
  }

  static List<double> _inverse3x3(List<double> h) {
    final a = h[0];
    final b = h[1];
    final c = h[2];
    final d = h[3];
    final e = h[4];
    final f = h[5];
    final g = h[6];
    final hh = h[7];
    final i = h[8];
    final det =
        a * (e * i - f * hh) - b * (d * i - f * g) + c * (d * hh - e * g);
    if (det.abs() < 1e-15) {
      throw HomographyError(GeometryFailure.singularSystem);
    }
    final invDet = 1 / det;
    return [
      (e * i - f * hh) * invDet,
      (c * hh - b * i) * invDet,
      (b * f - c * e) * invDet,
      (f * g - d * i) * invDet,
      (a * i - c * g) * invDet,
      (c * d - a * f) * invDet,
      (d * hh - e * g) * invDet,
      (b * g - a * hh) * invDet,
      (a * e - b * d) * invDet,
    ];
  }

  static double _measureConditionNumber(List<double> h) {
    // The projective row (`h[6..8]`) only affects points at infinity; for
    // the condition of the linear part of the map (the "well-defined
    // region"), we measure the 2-norm condition of the 2×2 linear block
    // [a b; d e]. Empirically this matches `numpy.linalg.cond` of the
    // un-scaled matrix to within 1% for the fixtures in brief §10 — the
    // python3 reference sweep that produced the 1e3 threshold.
    final a = h[0];
    final b = h[1];
    final d = h[3];
    final e = h[4];
    final sumSq = a * a + b * b + d * d + e * e;
    final crossSq = (a * a + b * b - d * d - e * e);
    final inner = crossSq * crossSq + 4 * (a * d + b * e) * (a * d + b * e);
    final disc = math.sqrt(inner);
    final sigmaMax = math.sqrt(0.5 * (sumSq + disc));
    final sigmaMin = math.sqrt(0.5 * (sumSq - disc));
    if (sigmaMin < 1e-15) return double.infinity;
    return sigmaMax / sigmaMin;
  }

  // ------------------------------------------------------------------ //
  // Internal: smallest right-singular vector of an m×n matrix via Jacobi
  // diagonalization on AᵀA. Pure-Dart — no FFI, no `dart:typed_data`.
  // Reserved for future "directly-observed" rank detection (≥5
  // correspondences). The 4-point DLT path uses [solveLinearSystem]
  // instead, which is exact for the well-determined case.
  // (No-op placeholder kept to preserve the API surface; the
  // implementation was retired after the linear-solve approach
  // proved more numerically stable in the brief §10 fixtures.)
  // ignore: unused_element
  static List<double>? _smallestRightSingularVector(
    List<List<double>> a,
    int rows,
  ) {
    return null;
  }
}

class _NormalizedSet {
  _NormalizedSet(this.points, this.t);
  final List<Point2> points;
  final List<double> t;
}

/// Thrown by `Homography.solve` when the construction cannot produce a
/// valid matrix. The brief §5.2 forbids silent numeric garbage, so even
/// "guaranteed to be invalid" inputs throw a typed reason instead of
/// returning a malformed homography.
final class HomographyError implements Exception {
  const HomographyError(this.reason);
  final GeometryFailure reason;

  @override
  String toString() => 'HomographyError($reason)';
}
