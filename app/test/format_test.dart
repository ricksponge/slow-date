import 'package:flutter_test/flutter_test.dart';
import 'package:slow_date/util/format.dart';

void main() {
  test('formatRemaining', () {
    expect(formatRemaining(const Duration(hours: 49, minutes: 5)), '2 j 01 h');
    expect(formatRemaining(const Duration(hours: 5, minutes: 3)), '5 h 03 min');
    expect(formatRemaining(const Duration(minutes: 4, seconds: 9)), '4 min 09 s');
    expect(formatRemaining(const Duration(seconds: -3)), '0 min');
  });
}
