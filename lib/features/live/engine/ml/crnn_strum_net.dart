import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart forward pass of the trained strum-direction CRNN
/// (ml-track P1.3, revised 2026-07-13: hand-written inference instead of
/// tflite_flutter — the net is ~350k params / ~1 ms per window, host-testable
/// on any platform, and keeps the ONE-win32-major rule untouched).
///
/// Architecture (must mirror `ml/train.py::build_model` exactly):
///   log-mel window (frames, mels) → standardise (per-mel mean/std) →
///   3 × [Conv2D 3×3 same + ReLU → MaxPool (1,2)] → per-frame flatten →
///   GRU(128, reset_after) → Dense(2) softmax = P(down), P(up).
///
/// Weights come from `assets/ml/strum_crnn.bin`, written by
/// `ml/export_dart_weights.py`; parity with the Keras reference is locked by
/// test/features/live/ml/crnn_strum_net_test.dart (<=1e-3).
class CrnnStrumNet {
  CrnnStrumNet._(this._arrays);

  final Map<String, _NdArray> _arrays;

  /// Model input frame count (PRE + POST of `ml/features.py::window_at`).
  int get frames => 15;

  /// Model input mel-band count.
  int get mels => _arrays['mean']!.dims[0];

  /// Parses the `SSML` v1 binary written by ml/export_dart_weights.py:
  /// magic | u32 version | u32 count | per array:
  /// u32 nameLen | utf8 name | u32 ndim | u32 dims[ndim] | f32 data.
  static CrnnStrumNet parse(ByteData bytes) {
    var off = 0;
    int u32() {
      final v = bytes.getUint32(off, Endian.little);
      off += 4;
      return v;
    }

    final magic = String.fromCharCodes(
        [for (var i = 0; i < 4; i++) bytes.getUint8(off + i)]);
    off += 4;
    if (magic != 'SSML') {
      throw FormatException('not a strum_crnn.bin (magic $magic)');
    }
    final version = u32();
    if (version != 1) throw FormatException('unknown version $version');

    final count = u32();
    final arrays = <String, _NdArray>{};
    for (var a = 0; a < count; a++) {
      final nameLen = u32();
      final name = String.fromCharCodes(
          [for (var i = 0; i < nameLen; i++) bytes.getUint8(off + i)]);
      off += nameLen;
      final ndim = u32();
      final dims = [for (var i = 0; i < ndim; i++) u32()];
      final n = dims.fold(1, (p, d) => p * d);
      final data = Float64List(n);
      for (var i = 0; i < n; i++) {
        data[i] = bytes.getFloat32(off, Endian.little);
        off += 4;
      }
      arrays[name] = _NdArray(dims, data);
    }
    const required = [
      'conv1_k', 'conv1_b', 'conv2_k', 'conv2_b', 'conv3_k', 'conv3_b', //
      'gru_k', 'gru_rk', 'gru_b', 'dense_k', 'dense_b', 'mean', 'std',
    ];
    for (final r in required) {
      if (!arrays.containsKey(r)) throw FormatException('missing array $r');
    }
    return CrnnStrumNet._(arrays);
  }

  /// Softmax [P(down), P(up)] for one RAW (un-normalised) log-mel window of
  /// [frames] rows × [mels] columns.
  List<double> forward(List<List<double>> window) {
    final mean = _arrays['mean']!.data;
    final std = _arrays['std']!.data;
    final f = window.length;
    final m = window.first.length;

    // Standardise into (f, m, 1) — channel-last like Keras.
    var x = _Tensor3(f, m, 1);
    for (var i = 0; i < f; i++) {
      for (var j = 0; j < m; j++) {
        x.set(i, j, 0, (window[i][j] - mean[j]) / std[j]);
      }
    }

    x = _maxPoolW2(_conv3x3Relu(x, _arrays['conv1_k']!, _arrays['conv1_b']!));
    x = _maxPoolW2(_conv3x3Relu(x, _arrays['conv2_k']!, _arrays['conv2_b']!));
    x = _maxPoolW2(_conv3x3Relu(x, _arrays['conv3_k']!, _arrays['conv3_b']!));

    // Per-frame flatten (Keras Reshape((frames, -1)) is C-order: w, then c).
    final stepLen = x.w * x.c;
    final h = _gruLastState(x, stepLen);

    // Dense(2) softmax.
    final dk = _arrays['dense_k']!; // (units, 2)
    final db = _arrays['dense_b']!.data;
    final logits = List<double>.filled(2, 0);
    for (var c = 0; c < 2; c++) {
      var acc = db[c];
      for (var u = 0; u < h.length; u++) {
        acc += h[u] * dk.data[u * 2 + c];
      }
      logits[c] = acc;
    }
    final peak = math.max(logits[0], logits[1]);
    final e0 = math.exp(logits[0] - peak);
    final e1 = math.exp(logits[1] - peak);
    return [e0 / (e0 + e1), e1 / (e0 + e1)];
  }

  /// Conv2D 3×3, stride 1, SAME zero padding, ReLU. Kernel (3,3,in,out),
  /// repacked per tap to [o][c] so the inner channel loop reads BOTH the
  /// input row and the kernel row contiguously (r171: this halves the
  /// forward cost — the original [c][o] layout strided the kernel by outC
  /// every step).
  static _Tensor3 _conv3x3Relu(_Tensor3 x, _NdArray k, _NdArray b) {
    final outC = k.dims[3];
    final inC = k.dims[2];
    final kPacked = k.packedConv ??= _packConv(k, inC, outC);
    final out = _Tensor3(x.h, x.w, outC);
    final xData = x.data;
    final outData = out.data;
    for (var i = 0; i < x.h; i++) {
      for (var j = 0; j < x.w; j++) {
        final outBase = (i * x.w + j) * outC;
        for (var o = 0; o < outC; o++) {
          outData[outBase + o] = b.data[o];
        }
        for (var di = -1; di <= 1; di++) {
          final ii = i + di;
          if (ii < 0 || ii >= x.h) continue;
          for (var dj = -1; dj <= 1; dj++) {
            final jj = j + dj;
            if (jj < 0 || jj >= x.w) continue;
            final tap = ((di + 1) * 3 + (dj + 1)) * inC * outC;
            final xBase = (ii * x.w + jj) * x.c;
            for (var o = 0; o < outC; o++) {
              final kBase = tap + o * inC;
              var acc = 0.0;
              for (var c = 0; c < inC; c++) {
                acc += xData[xBase + c] * kPacked[kBase + c];
              }
              outData[outBase + o] += acc;
            }
          }
        }
        for (var o = 0; o < outC; o++) {
          final v = outData[outBase + o];
          if (v < 0) outData[outBase + o] = 0;
        }
      }
    }
    return out;
  }

  /// One-time repack of a (3,3,in,out) kernel to per-tap [o][c] rows.
  static Float64List _packConv(_NdArray k, int inC, int outC) {
    final packed = Float64List(9 * inC * outC);
    for (var t = 0; t < 9; t++) {
      for (var c = 0; c < inC; c++) {
        for (var o = 0; o < outC; o++) {
          packed[t * inC * outC + o * inC + c] =
              k.data[t * inC * outC + c * outC + o];
        }
      }
    }
    return packed;
  }

  /// MaxPool2D pool (1,2), stride (1,2), VALID — halves the mel axis.
  static _Tensor3 _maxPoolW2(_Tensor3 x) {
    final out = _Tensor3(x.h, x.w ~/ 2, x.c);
    for (var i = 0; i < out.h; i++) {
      for (var j = 0; j < out.w; j++) {
        for (var c = 0; c < x.c; c++) {
          out.set(i, j, c,
              math.max(x.get(i, 2 * j, c), x.get(i, 2 * j + 1, c)));
        }
      }
    }
    return out;
  }

  /// Keras GRU (reset_after=true, tanh/sigmoid), returning the LAST hidden
  /// state. Gate column order in both kernels is [z | r | h]; bias row 0 is
  /// the input bias, row 1 the recurrent bias.
  Float64List _gruLastState(_Tensor3 x, int stepLen) {
    final gk = _arrays['gru_k']!; // (stepLen, 3*units)
    final grk = _arrays['gru_rk']!; // (units, 3*units)
    final gb = _arrays['gru_b']!; // (2, 3*units)
    final units = grk.dims[0];
    final g3 = 3 * units;
    assert(gk.dims[0] == stepLen, 'GRU input ${gk.dims[0]} != conv $stepLen');

    final h = Float64List(units);
    final xg = Float64List(g3);
    final hg = Float64List(g3);
    for (var t = 0; t < x.h; t++) {
      // Input projection: xg = x_t · Wk + b_in.
      for (var g = 0; g < g3; g++) {
        xg[g] = gb.data[g];
      }
      final xBase = t * stepLen;
      for (var i = 0; i < stepLen; i++) {
        final v = x.data[xBase + i];
        if (v == 0) continue; // post-ReLU sparsity — skip zero rows
        final kBase = i * g3;
        for (var g = 0; g < g3; g++) {
          xg[g] += v * gk.data[kBase + g];
        }
      }
      // Recurrent projection: hg = h · Wrk + b_rec.
      for (var g = 0; g < g3; g++) {
        hg[g] = gb.data[g3 + g];
      }
      for (var u = 0; u < units; u++) {
        final v = h[u];
        if (v == 0) continue;
        final kBase = u * g3;
        for (var g = 0; g < g3; g++) {
          hg[g] += v * grk.data[kBase + g];
        }
      }
      for (var u = 0; u < units; u++) {
        final z = _sigmoid(xg[u] + hg[u]);
        final r = _sigmoid(xg[units + u] + hg[units + u]);
        final hh = _tanh(xg[2 * units + u] + r * hg[2 * units + u]);
        h[u] = z * h[u] + (1 - z) * hh;
      }
    }
    return h;
  }

  static double _sigmoid(double v) => 1.0 / (1.0 + math.exp(-v));

  static double _tanh(double v) {
    final e = math.exp(2 * v);
    return e.isInfinite ? 1.0 : (e - 1) / (e + 1);
  }
}

class _NdArray {
  _NdArray(this.dims, this.data);
  final List<int> dims;
  final Float64List data;

  /// Lazily repacked conv layout (see _packConv) — computed once per net.
  Float64List? packedConv;
}

class _Tensor3 {
  _Tensor3(this.h, this.w, this.c) : data = Float64List(h * w * c);
  final int h;
  final int w;
  final int c;
  final Float64List data;

  double get(int i, int j, int k) => data[(i * w + j) * c + k];
  void set(int i, int j, int k, double v) => data[(i * w + j) * c + k] = v;
}
