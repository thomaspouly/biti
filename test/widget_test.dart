import 'package:biti/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Biti affiche la grille et les actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BitiApp());

    expect(find.text('Biti'), findsOneWidget);
    expect(find.text('Nourrir'), findsOneWidget);
    expect(find.text('Jouer'), findsOneWidget);
    expect(find.text('Faim'), findsOneWidget);
    expect(find.text('Énergie'), findsOneWidget);
    expect(find.text('Humeur'), findsOneWidget);
  });
}
