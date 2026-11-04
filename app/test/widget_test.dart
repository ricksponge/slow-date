// Présent pour que `flutter create` ne génère pas son test d'exemple (qui référence MyApp).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slow_date/widgets/countdown.dart';

void main() {
  testWidgets('Countdown affiche le temps restant', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Countdown(target: DateTime.now().add(const Duration(hours: 5, minutes: 30)), prefix: 'Reste '),
    ));
    expect(find.textContaining('Reste 5 h'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // arrête le minuteur
  });
}
