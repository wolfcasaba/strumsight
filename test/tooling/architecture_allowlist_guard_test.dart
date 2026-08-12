import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_architecture.dart';

void main() {
  test('cross-feature architecture allowlist does not grow', () {
    expect(architectureAllowlist.length, lessThanOrEqualTo(12));
  });
}
