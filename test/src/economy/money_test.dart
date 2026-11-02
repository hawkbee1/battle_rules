import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  group('MoneyRules on the fixtures', () {
    // Fixture economy: hit 2, kill 6, construction 4, heal 3, HQ hit 12,
    // HQ destruction 90; default price 80, camp 450; fees 1 % inside a
    // guild, 5 % outside; minimum 400.
    late GameData data;
    late MoneyRules money;

    setUp(() {
      data = parseFixtures();
      money = MoneyRules(data.economy);
    });

    UnitType type(String id) => data.units.unitTypes[id]!;

    PurchaseRefusal? refusal(Purchase purchase) => switch (purchase) {
      PurchaseRefused(:final reason) => reason,
      Bought() => null,
    };

    test('ECO-02 ECO-18 HQ-04 each earning pays the acting section', () {
      expect(money.earned(const HitEarning()), 2);
      expect(money.earned(const KillEarning()), 6);
      expect(money.earned(const ConstructionEarning()), 4);
      expect(money.earned(const HqHitEarning()), 12);
      expect(money.earned(const HqDestroyedEarning()), 90);
    });

    test('ECO-02 decision 201 a killing shot earns its hit and its kill', () {
      expect(
        money.earned(const HitEarning()) + money.earned(const KillEarning()),
        8,
      );
    });

    test('ECO-02 decision 202 allies and the own HQ earn nothing', () {
      expect(money.earned(const HitEarning(ally: true)), 0);
      expect(money.earned(const KillEarning(ally: true)), 0);
      expect(money.earned(const HqHitEarning(own: true)), 0);
      expect(money.earned(const HqDestroyedEarning(own: true)), 0);
    });

    test('ECO-03 a medic earns money when healing; others do not', () {
      expect(money.earned(HealEarning(type('medic'))), 3);
      expect(money.earned(HealEarning(type('engineer'))), 0);
    });

    test('ECO-15 ECO-22 a construction earns every time, with no limit', () {
      final earnings = [
        for (var build = 0; build < 5; build++)
          money.earned(const ConstructionEarning()),
      ];

      expect(earnings, List.filled(5, 4));
    });

    test('ECO-04 UNIT-27 the commander buys a unit with section money', () {
      final bought = money.buyUnit(
        type: type('jeep'),
        money: 100,
        hasRoom: true,
        locked: false,
        arrivalBlocked: false,
      ) as Bought;

      expect(bought.price, 80);
      expect(bought.moneyLeft, 20);
    });

    test('ECO-04 decision 130 buying needs free room and enough money', () {
      expect(
        refusal(
          money.buyUnit(
            type: type('jeep'),
            money: 100,
            hasRoom: false,
            locked: false,
            arrivalBlocked: false,
          ),
        ),
        PurchaseRefusal.noRoom,
      );
      expect(
        refusal(
          money.buyUnit(
            type: type('jeep'),
            money: 79,
            hasRoom: true,
            locked: false,
            arrivalBlocked: false,
          ),
        ),
        PurchaseRefusal.notEnoughMoney,
      );
      expect(
        refusal(
          money.buyUnit(
            type: type('jeep'),
            money: 80,
            hasRoom: true,
            locked: false,
            arrivalBlocked: false,
          ),
        ),
        isNull,
      );
    });

    test('ECO-07 HQ-35 HQ-46 decision 205 nothing is bought while the '
        'section is locked or its arrival blocked', () {
      Purchase jeep({bool locked = false, bool arrivalBlocked = false}) =>
          money.buyUnit(
            type: type('jeep'),
            money: 100,
            hasRoom: true,
            locked: locked,
            arrivalBlocked: arrivalBlocked,
          );

      expect(refusal(jeep(locked: true)), PurchaseRefusal.sectionLocked);
      expect(
        refusal(jeep(arrivalBlocked: true)),
        PurchaseRefusal.arrivalBlocked,
      );
      expect(refusal(jeep()), isNull);
    });

    test(
      'decision 205 the guild camp arrives at the HQ: blocked there too',
      () {
        expect(
          refusal(
            money.buyUnit(
              type: type('camp'),
              money: 450,
              hasRoom: false,
              locked: false,
              arrivalBlocked: true,
              guildChief: true,
            ),
          ),
          PurchaseRefusal.arrivalBlocked,
        );
      },
    );

    test('ECO-05 the commander buys radios', () {
      expect(
        money.buyUnit(
          type: type('radio'),
          money: 80,
          hasRoom: true,
          locked: false,
          arrivalBlocked: false,
        ),
        isA<Bought>(),
      );
    });

    test('UNIT-41 a commander is never bought', () {
      expect(
        refusal(
          money.buyUnit(
            type: type('commander'),
            money: 1000,
            hasRoom: true,
            locked: false,
            arrivalBlocked: false,
          ),
        ),
        PurchaseRefusal.notForSale,
      );
    });

    test('ECO-06 HQ-42 HQ-43 only the guild chief buys the camp, one at a '
        'time, outside the cap', () {
      Purchase camp({bool chief = true, bool exists = false}) => money.buyUnit(
        type: type('camp'),
        money: 450,
        hasRoom: false,
        locked: false,
        arrivalBlocked: false,
        guildChief: chief,
        guildHasCamp: exists,
      );

      expect((camp() as Bought).price, 450);
      expect(refusal(camp(chief: false)), PurchaseRefusal.notGuildChief);
      expect(refusal(camp(exists: true)), PurchaseRefusal.campExists);
    });

    test('COMBAT-27 a weapon is bought with section money and needs no '
        'room', () {
      final rifle = data.combat.weaponTypes['rifle']!;

      expect(
        (money.buyWeapon(weapon: rifle, money: 90) as Bought).moneyLeft,
        10,
      );
      expect(
        refusal(money.buyWeapon(weapon: rifle, money: 79)),
        PurchaseRefusal.notEnoughMoney,
      );
    });

    test('ECO-08 ECO-09 ECO-11 decision 203 the fee comes out of the amount '
        'and is destroyed', () {
      final outside = money.transfer(
        amount: 100,
        senderMoney: 100,
        sameTeam: true,
        sameGuild: false,
      ) as Transferred;
      final inside = money.transfer(
        amount: 100,
        senderMoney: 100,
        sameTeam: true,
        sameGuild: true,
      ) as Transferred;

      expect((outside.received, outside.fee), (95, 5));
      expect((inside.received, inside.fee), (99, 1));
    });

    test('ECO-16 decision 200 a fee rounds to whole w€, halves up', () {
      int fee(int amount) => (money.transfer(
        amount: amount,
        senderMoney: amount,
        sameTeam: true,
        sameGuild: false,
      ) as Transferred).fee;

      // 5 % of 9 is 0.45, of 10 is 0.5, of 29 is 1.45, of 30 is 1.5.
      expect([9, 10, 29, 30].map(fee), [0, 1, 1, 2]);
    });

    test('ECO-10 money moves only inside a team', () {
      expect(
        money.transfer(
          amount: 10,
          senderMoney: 100,
          sameTeam: false,
          sameGuild: false,
        ),
        isA<TransferRefused>().having(
          (refused) => refused.reason,
          'reason',
          TransferRefusal.otherTeam,
        ),
      );
    });

    test('a transfer needs a positive amount the sender has', () {
      TransferRefusal? reason(int amount) => switch (money.transfer(
        amount: amount,
        senderMoney: 50,
        sameTeam: true,
        sameGuild: true,
      )) {
        TransferRefused(:final reason) => reason,
        Transferred() => null,
      };

      expect(reason(0), TransferRefusal.notPositive);
      expect(reason(51), TransferRefusal.notEnoughMoney);
      expect(reason(50), isNull);
    });

    test('SOC-10 ECO-13 the safety net after a commander death', () {
      expect(money.afterCommanderDeath(120, warMinStartingMoney: 400), 400);
      expect(money.afterCommanderDeath(900, warMinStartingMoney: 400), 900);
    });

    test('SOC-10 ECO-13 the safety net after the last unit, not before', () {
      expect(
        money.afterUnitLost(120, unitsLeft: 0, warMinStartingMoney: 400),
        400,
      );
      expect(
        money.afterUnitLost(120, unitsLeft: 1, warMinStartingMoney: 400),
        120,
      );
    });

    test('ECO-14 SOC-14 giving money away then losing everything refills to '
        'the minimum', () {
      final gift = money.transfer(
        amount: 300,
        senderMoney: 300,
        sameTeam: true,
        sameGuild: false,
      ) as Transferred;

      expect(gift.fee, 15);
      expect(
        money.afterUnitLost(0, unitsLeft: 0, warMinStartingMoney: 400),
        400,
      );
    });

    test(
      "SOC-11 SOC-15 UNIT-41 a new section starts with its war's minimum",
      () {
        expect(money.startingMoney(650), 650);
      },
    );
  });

  group('MoneyRules on the plan data', () {
    late GameData data;
    late MoneyRules money;

    setUp(() {
      data = parsePlanData();
      money = MoneyRules(data.economy);
    });

    test('ECO-16 ECO-17 ECO-20 HQ-43 the plan prices and starting money', () {
      expect(data.economy.currency, 'w€');
      expect(data.economy.priceOf('soldier'), 100);
      expect(data.economy.priceOf('encampment'), 500);
      expect(data.economy.minStartingMoney, 500);
      expect(money.startingMoney(data.economy.minStartingMoney), 500);
    });

    test('ECO-18 the plan earnings', () {
      expect(
        [
          const HitEarning(),
          const KillEarning(),
          const ConstructionEarning(),
          HealEarning(data.units.unitTypes['medic']!),
          const HqHitEarning(),
          const HqDestroyedEarning(),
        ].map(money.earned),
        [1, 5, 5, 5, 10, 100],
      );
    });

    test('ECO-19 a transfer of 100 w€ loses 2 inside a guild, 7 outside', () {
      int fee({required bool sameGuild}) => (money.transfer(
        amount: 100,
        senderMoney: 100,
        sameTeam: true,
        sameGuild: sameGuild,
      ) as Transferred).fee;

      expect(fee(sameGuild: true), 2);
      expect(fee(sameGuild: false), 7);
    });

    test('ECO-21 XP cannot be bought', () {
      expect(data.economy.xpPurchasable, isFalse);
    });

    test('decision 145 the guild camp heals earn money too', () {
      expect(money.earned(HealEarning(data.units.unitTypes['encampment']!)), 5);
    });
  });
}
