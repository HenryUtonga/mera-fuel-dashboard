import 'package:flutter_test/flutter_test.dart';
import 'package:mera_fuel_dashboard/main.dart';

void main() {
  testWidgets('MERA Fuel Control dashboard loads', (tester) async {
    await tester.pumpWidget(const MeraFuelDashboardApp());

    expect(find.text('MERA'), findsOneWidget);
    expect(find.text('FUEL CONTROL'), findsOneWidget);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Active Stations'), findsOneWidget);
    expect(find.text('Petrol Stock'), findsOneWidget);
    expect(find.text('Diesel Stock'), findsOneWidget);
  });
}
