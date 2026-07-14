import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart forward pass of the trained full-band CHORD CRNN
/// (ml-chord-track ship-path step 3, r196).
///
/// Same self-describing little-endian float32 container as the shipped strum
/// net (`crnn_strum_net.dart`) — only the MAGIC ('CCRN' vs 'SSML') and the
/// array set differ (this model adds BatchNorm, an extra Dense(128) before the
/// recurrent layer, and is Bidirectional). The Conv2D / BatchNorm / reset_after
/// GRU / Dense / softmax building blocks are adapted DIRECTLY from
/// `CrnnStrumNet` so both nets share the same verified math.
///
/// Architecture — mirrors `ml/chords/train_chord.py::build_chord_model` and the
/// r195 export contract in `ml/chords/export_chord_dart.py` EXACTLY:
///   CQT (T,144) → normalise per bin (x-mean)/std → (T,144,1) →
///   3 × [Conv2D 3×3 same + ReLU → BatchNorm(eps 1e-3) → MaxPool (1,2) freq] →
///     channels 16→32→32, freq 144→72→36→18 → (T,18,32) →
///   per-frame flatten (C-order: freq, then channel) → (T,576) →
///   TimeDistributed Dense(128)+ReLU → (T,128) →
///   Bidirectional GRU(96) reset_after, gate order [z,r,h], forward ++ backward
///     concatenated → (T,192) →
///   TimeDistributed Dense(25) + softmax → (T,25) per-frame posteriors.
///
/// Weights come from `assets/ml/chord_crnn.bin`; parity with the Keras
/// reference is locked to <=1e-3 by
/// test/features/live/ml/chord_crnn_parity_test.dart.
class ChordCrnn {
  ChordCrnn._(this._arrays);

  final Map<String, _NdArray> _arrays;

  /// Model input frequency-bin count (CQT bins).
  int get nBins => _arrays['mean']!.dims[0];

  /// Output class count (25 = N.C. + 12 major + 12 minor, MIREX majmin).
  int get nClasses => _arrays['dense2_b']!.dims[0];

  /// Parses the `CCRN` v1 binary written by ml/chords/export_chord_dart.py:
  /// magic | u32 version | u32 count | per array:
  /// u32 nameLen | utf8 name | u32 ndim | u32 dims[ndim] | f32 data.
  static ChordCrnn parse(ByteData bytes) {
    var off = 0;
    int u32() {
      final v = bytes.getUint32(off, Endian.little);
      off += 4;
      return v;
    }

    final magic = String.fromCharCodes(
        [for (var i = 0; i < 4; i++) bytes.getUint8(off + i)]);
    off += 4;
    if (magic != 'CCRN') {
      throw FormatException('not a chord_crnn.bin (magic $magic)');
    }
    final version = u32();
    if (version != 1) throw FormatException('unknown version $version');

    final count = u32();
    if (count != 30) throw FormatException('expected 30 arrays, got $count');
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
      'conv1_k', 'conv1_b', 'bn1_gamma', 'bn1_beta', 'bn1_mean', 'bn1_var', //
      'conv2_k', 'conv2_b', 'bn2_gamma', 'bn2_beta', 'bn2_mean', 'bn2_var',
      'conv3_k', 'conv3_b', 'bn3_gamma', 'bn3_beta', 'bn3_mean', 'bn3_var',
      'dense1_k', 'dense1_b',
      'gru_fwd_k', 'gru_fwd_rk', 'gru_fwd_b',
      'gru_bwd_k', 'gru_bwd_rk', 'gru_bwd_b',
      'dense2_k', 'dense2_b', 'mean', 'std',
    ];
    for (final r in required) {
      if (!arrays.containsKey(r)) throw FormatException('missing array $r');
    }
    return ChordCrnn._(arrays);
  }

  /// Per-frame 25-dim softmax over a RAW (un-normalised) CQT of `T` rows ×
  /// [nBins] columns. Returns `T` `Float32List`s of length [nClasses].
  List<Float32List> infer(List<List<double>> cqt) {
    final mean = _arrays['mean']!.data;
    final std = _arrays['std']!.data;
    final t = cqt.length;
    final m = nBins;

    // Normalise into (T, nBins, 1) — channel-last like Keras.
    var x = _Tensor3(t, m, 1);
    for (var i = 0; i < t; i++) {
      final row = cqt[i];
      for (var j = 0; j < m; j++) {
        x.set(i, j, 0, (row[j] - mean[j]) / std[j]);
      }
    }

    // 3 conv blocks: Conv2D(relu) → BatchNorm(eps 1e-3) → MaxPool (1,2) freq.
    x = _block(x, 'conv1', 'bn1');
    x = _block(x, 'conv2', 'bn2');
    x = _block(x, 'conv3', 'bn3');

    // Per-frame flatten (Keras Reshape((T,-1)) is C-order: freq w, then chan c).
    final stepLen = x.w * x.c; // 18 * 32 = 576

    // TimeDistributed Dense(128) + ReLU.
    final d1k = _arrays['dense1_k']!; // (576, 128)
    final d1b = _arrays['dense1_b']!.data; // (128,)
    final units1 = d1b.length;
    final feats = List<Float64List>.generate(t, (_) => Float64List(units1));
    for (var i = 0; i < t; i++) {
      final xBase = i * stepLen;
      final f = feats[i];
      for (var o = 0; o < units1; o++) {
        var acc = d1b[o];
        for (var s = 0; s < stepLen; s++) {
          acc += x.data[xBase + s] * d1k.data[s * units1 + o];
        }
        f[o] = acc < 0 ? 0 : acc; // ReLU
      }
    }

    // Bidirectional GRU(96), reset_after, gate order [z,r,h].
    final fwd = _gruSeq(feats, 'gru_fwd', reverse: false);
    final bwd = _gruSeq(feats, 'gru_bwd', reverse: true);

    // Concat forward ++ backward → (T, 192), then Dense(25) + softmax.
    final d2k = _arrays['dense2_k']!; // (192, 25)
    final d2b = _arrays['dense2_b']!.data; // (25,)
    final n = nClasses;
    final gu = fwd[0].length; // 96
    final out = <Float32List>[];
    final logits = List<double>.filled(n, 0);
    for (var i = 0; i < t; i++) {
      final hf = fwd[i];
      final hb = bwd[i];
      for (var c = 0; c < n; c++) {
        var acc = d2b[c];
        for (var u = 0; u < gu; u++) {
          acc += hf[u] * d2k.data[u * n + c];
        }
        for (var u = 0; u < gu; u++) {
          acc += hb[u] * d2k.data[(gu + u) * n + c];
        }
        logits[c] = acc;
      }
      out.add(_softmax(logits));
    }
    return out;
  }

  /// One conv block: Conv2D 3×3 SAME + ReLU → BatchNorm(eps 1e-3) →
  /// MaxPool (1,2) (freq halved, time kept). ReLU is applied BEFORE BN, exactly
  /// as the Keras Conv2D(activation="relu") → BatchNormalization graph.
  _Tensor3 _block(_Tensor3 x, String conv, String bn) {
    var y = _conv3x3Relu(x, _arrays['${conv}_k']!, _arrays['${conv}_b']!);
    y = _batchNorm(y, _arrays['${bn}_gamma']!, _arrays['${bn}_beta']!,
        _arrays['${bn}_mean']!, _arrays['${bn}_var']!);
    return _maxPoolW2(y);
  }

  /// Keras BatchNormalization (inference, axis=-1 channels, eps=1e-3):
  ///   y = gamma * (x - moving_mean) / sqrt(moving_var + eps) + beta
  /// Applied in place per channel.
  static _Tensor3 _batchNorm(
      _Tensor3 x, _NdArray gamma, _NdArray beta, _NdArray mean, _NdArray var_) {
    const eps = 1e-3;
    final c = x.c;
    final scale = Float64List(c);
    final shift = Float64List(c);
    for (var k = 0; k < c; k++) {
      final inv = 1.0 / math.sqrt(var_.data[k] + eps);
      scale[k] = gamma.data[k] * inv;
      shift[k] = beta.data[k] - mean.data[k] * scale[k];
    }
    final data = x.data;
    final len = data.length;
    for (var i = 0; i < len; i++) {
      final k = i % c;
      data[i] = data[i] * scale[k] + shift[k];
    }
    return x;
  }

  /// Conv2D 3×3, stride 1, SAME zero padding, ReLU. Kernel (3,3,in,out),
  /// repacked per tap to [o][c] so the inner channel loop reads both the input
  /// row and the kernel row contiguously (adapted from CrnnStrumNet).
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
          if (outData[outBase + o] < 0) outData[outBase + o] = 0;
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

  /// MaxPool2D pool (1,2), stride (1,2), VALID — halves the freq (w) axis.
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

  /// Keras GRU (reset_after=true, tanh/sigmoid) returning the FULL sequence.
  /// Gate column order in both kernels is [z | r | h]; bias row 0 is the input
  /// bias, row 1 the recurrent bias. Adapted from CrnnStrumNet._gruLastState —
  /// this variant stores the hidden state per time step and can run backward.
  ///
  /// For [reverse]=true the sequence is consumed t=T-1..0 and each output is
  /// stored at its ORIGINAL time index, so the caller can concat forward and
  /// backward frame-aligned exactly like Keras Bidirectional(merge='concat').
  List<Float64List> _gruSeq(List<Float64List> xs, String prefix,
      {required bool reverse}) {
    final gk = _arrays['${prefix}_k']!; // (stepLen, 3*units)
    final grk = _arrays['${prefix}_rk']!; // (units, 3*units)
    final gb = _arrays['${prefix}_b']!; // (2, 3*units)
    final units = grk.dims[0];
    final g3 = 3 * units;
    final stepLen = gk.dims[0];
    final tn = xs.length;

    final outSeq = List<Float64List>.filled(tn, Float64List(0));
    final h = Float64List(units);
    final xg = Float64List(g3);
    final hg = Float64List(g3);
    for (var idx = 0; idx < tn; idx++) {
      final t = reverse ? tn - 1 - idx : idx;
      final xrow = xs[t];
      // Input projection: xg = x_t · Wk + b_in.
      for (var g = 0; g < g3; g++) {
        xg[g] = gb.data[g];
      }
      for (var i = 0; i < stepLen; i++) {
        final v = xrow[i];
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
      outSeq[t] = Float64List.fromList(h);
    }
    return outSeq;
  }

  static Float32List _softmax(List<double> logits) {
    final n = logits.length;
    var peak = logits[0];
    for (final l in logits) {
      if (l > peak) peak = l;
    }
    var sum = 0.0;
    final out = Float32List(n);
    for (var c = 0; c < n; c++) {
      final e = math.exp(logits[c] - peak);
      out[c] = e;
      sum += e;
    }
    for (var c = 0; c < n; c++) {
      out[c] = out[c] / sum;
    }
    return out;
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
