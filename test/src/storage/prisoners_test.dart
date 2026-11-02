import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

void main() {
  group('Prisoners', () {
    // Section a holds b1 and b2 of section b; section b holds a1 of a.
    final aHolds = const PrisonerStorage()
        .added('b1', ownerSectionId: 'b')
        .added('b2', ownerSectionId: 'b');
    final bHolds = const PrisonerStorage().added('a1', ownerSectionId: 'a');

    PrisonerDeal accept(PrisonerOffer offer, {int ownerMoney = 0}) =>
        offer.accept(
          captorPrisoners: aHolds,
          ownerPrisoners: bHolds,
          ownerMoney: ownerMoney,
        );

    DealRefusal? refusal(PrisonerDeal deal) => switch (deal) {
      DealRefused(:final reason) => reason,
      DealDone() => null,
    };

    ExchangeOffer exchange(List<String> released, List<String> wanted) =>
        ExchangeOffer(
          captorSectionId: 'a',
          ownerSectionId: 'b',
          released: released,
          wanted: wanted,
        );

    RansomOffer ransom(List<String> released, int price) => RansomOffer(
      captorSectionId: 'a',
      ownerSectionId: 'b',
      released: released,
      price: price,
    );

    test('COMBAT-43 HQ-37 the prisoner storage keeps each owner', () {
      expect(aHolds.prisoners, ['b1', 'b2']);
      expect(aHolds.holds(['b1', 'b2'], ownerSectionId: 'b'), isTrue);
      expect(aHolds.holds(['b1'], ownerSectionId: 'c'), isFalse);
      expect(aHolds.without(['b1']).prisoners, ['b2']);
    });

    test('COMBAT-44 an exchange: each released prisoner goes back to its '
        "owner's storage", () {
      final deal = accept(exchange(['b1'], ['a1'])) as DealDone;

      expect(deal.captorPrisoners.prisoners, ['b2']);
      expect(deal.ownerPrisoners.prisoners, isEmpty);
      expect(deal.ransom, 0);
    });

    test('COMBAT-44 a ransom goes entirely to the captor section, with no '
        'fee', () {
      final deal =
          accept(ransom(['b1', 'b2'], 150), ownerMoney: 150) as DealDone;

      expect(deal.ransom, 150);
      expect(deal.captorPrisoners.prisoners, isEmpty);
      expect(deal.ownerPrisoners.prisoners, ['a1']);
    });

    test('COMBAT-44 a ransom the owner cannot pay is refused', () {
      expect(
        refusal(accept(ransom(['b1'], 150), ownerMoney: 149)),
        DealRefusal.notEnoughMoney,
      );
    });

    test('COMBAT-44 each prisoner named must still be held by its side', () {
      expect(refusal(accept(exchange(['b3'], ['a1']))), DealRefusal.notHeld);
      expect(refusal(accept(exchange(['b1'], ['a2']))), DealRefusal.notHeld);
      // a holds b1 as a prisoner of b, not of c.
      expect(
        refusal(
          const ExchangeOffer(
            captorSectionId: 'a',
            ownerSectionId: 'c',
            released: ['b1'],
            wanted: ['a1'],
          ).accept(
            captorPrisoners: aHolds,
            ownerPrisoners: bHolds,
            ownerMoney: 0,
          ),
        ),
        DealRefusal.notHeld,
      );
    });

    test('COMBAT-44 an offer releases a prisoner and asks for one or for '
        'money', () {
      expect(
        refusal(accept(exchange([], ['a1']))),
        DealRefusal.nothingReleased,
      );
      expect(refusal(accept(exchange(['b1'], []))), DealRefusal.nothingAsked);
      expect(refusal(accept(ransom(['b1'], 0))), DealRefusal.nothingAsked);
    });
  });
}
