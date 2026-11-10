import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

void main() {
  group(EconomyData, () {
    late EconomyData economy;

    setUp(() {
      economy = EconomyData.parse(readFixture('economy.yaml'));
    });

    test('reads the version, currency and starting money', () {
      expect(economy.version, 1);
      expect(economy.currency, 'w€');
      expect(economy.minStartingMoney, 400);
    });

    test('reads the default and listed prices', () {
      expect(economy.defaultPrice, 80);
      expect(economy.prices, {'camp': 450, 'test_unit': 0});
    });

    test('priceOf gives the listed price, else the default price', () {
      expect(economy.priceOf('camp'), 450);
      expect(economy.priceOf('rifle'), 80);
    });

    test('reads the earnings', () {
      final earnings = economy.earnings;

      expect(earnings.hit, 2);
      expect(earnings.kill, 6);
      expect(earnings.construction, 4);
      expect(earnings.heal, 3);
      expect(earnings.hqHit, 12);
      expect(earnings.hqDestruction, 90);
    });

    test('reads the transfer fees and the other rules', () {
      expect(economy.transferFeeInsideGuild, 0.01);
      expect(economy.transferFeeOutsideGuild, 0.05);
      expect(economy.xpPurchasable, isFalse);
      expect(economy.buildDestroyFarmingLimit, 'none');
    });

    test('ECO-16 decision 200 rejects an amount that is not whole w€', () {
      expect(
        () => EconomyData.parse(
          readFixture('economy.yaml', {'camp: 450': 'camp: 450.5'}),
        ),
        throwsDataError('economy.yaml', 'prices.camp', 450.5, 'integer'),
      );
    });
  });
}
