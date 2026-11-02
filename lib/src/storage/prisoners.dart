/// {@template prisoner_storage}
/// A section's prisoners: separate from its unit storage, unlimited, never
/// counted in storage capacity (COMBAT-43, decision 94). It keeps each
/// prisoner's owner section, whose storage the prisoner returns to when
/// released (COMBAT-44). A prisoner stays from one battle of a war to the
/// next (UNIT-30) and is lost at the end of the war if never released
/// (COMBAT-45).
/// {@endtemplate}
final class PrisonerStorage {
  /// {@macro prisoner_storage}
  const new([this.owners = const {}]);

  /// The prisoners' owner section ids, by unit id.
  final Map<String, String> owners;

  /// The prisoners' unit ids.
  Iterable<String> get prisoners => owners.keys;

  /// This storage with [unitId], of the section [ownerSectionId], taken
  /// prisoner. There is no limit.
  PrisonerStorage added(String unitId, {required String ownerSectionId}) =>
      PrisonerStorage(Map.unmodifiable({...owners, unitId: ownerSectionId}));

  /// Whether it holds each of [unitIds] as a prisoner of [ownerSectionId].
  bool holds(Iterable<String> unitIds, {required String ownerSectionId}) =>
      unitIds.every((unitId) => owners[unitId] == ownerSectionId);

  /// This storage once [unitIds] are released.
  PrisonerStorage without(Iterable<String> unitIds) => PrisonerStorage(
    Map.unmodifiable({
      for (final MapEntry(:key, :value) in owners.entries)
        if (!unitIds.contains(key)) key: value,
    }),
  );
}

/// Why accepting a prisoner offer is refused.
enum DealRefusal {
  /// The offer releases no prisoner.
  nothingReleased,

  /// The offer asks for no prisoner and no money.
  nothingAsked,

  /// A prisoner it names is no longer held by that side.
  notHeld,

  /// The prisoners' owner has less money than the ransom.
  notEnoughMoney,
}

/// The outcome of accepting a prisoner offer.
sealed class PrisonerDeal {
  const new();
}

/// {@template deal_done}
/// The deal is done: the prisoners each side released are stored by
/// their owners again, and the captor section receives [ransom].
/// {@endtemplate}
final class DealDone extends PrisonerDeal {
  /// {@macro deal_done}
  const new({
    required this.captorPrisoners,
    required this.ownerPrisoners,
    required this.ransom,
  });

  /// The captor section's prisoner storage after the deal.
  final PrisonerStorage captorPrisoners;

  /// The prisoner storage of the prisoners' owner after the deal.
  final PrisonerStorage ownerPrisoners;

  /// The money the owner pays the captor section: all of it, with no fee;
  /// 0 for an exchange.
  final int ransom;
}

/// {@template deal_refused}
/// Nothing changes, for [reason].
/// {@endtemplate}
final class DealRefused extends PrisonerDeal {
  /// {@macro deal_refused}
  const new(this.reason);

  /// Why.
  final DealRefusal reason;
}

/// {@template prisoner_offer}
/// An offer the owner of [captorSectionId] posts in game to the owner of
/// [ownerSectionId] to release the prisoners [released], all of that
/// section; the owner accepts or refuses it (COMBAT-44).
/// {@endtemplate}
sealed class PrisonerOffer {
  /// {@macro prisoner_offer}
  const new({
    required this.captorSectionId,
    required this.ownerSectionId,
    required this.released,
  });

  /// The captor section, which posts the offer.
  final String captorSectionId;

  /// The prisoners' owner section, which accepts or refuses it.
  final String ownerSectionId;

  /// The prisoners the captor releases.
  final List<String> released;

  /// The offer accepted by the owner of [ownerSectionId], who has
  /// [ownerMoney], with both sides' prisoner storages as they are then.
  ///
  /// Each prisoner named must still be held by its side, as a prisoner of
  /// the other side. A ransom goes entirely to the captor section, with no
  /// fee, even across teams.
  PrisonerDeal accept({
    required PrisonerStorage captorPrisoners,
    required PrisonerStorage ownerPrisoners,
    required int ownerMoney,
  }) {
    final (wanted, ransom) = switch (this) {
      ExchangeOffer(:final wanted) => (wanted, 0),
      RansomOffer(:final price) => (const <String>[], price),
    };
    final refusal = switch (this) {
      _ when released.isEmpty => DealRefusal.nothingReleased,
      _ when wanted.isEmpty && ransom <= 0 => DealRefusal.nothingAsked,
      _ when !captorPrisoners.holds(released, ownerSectionId: ownerSectionId) =>
        DealRefusal.notHeld,
      _ when !ownerPrisoners.holds(wanted, ownerSectionId: captorSectionId) =>
        DealRefusal.notHeld,
      _ when ransom > ownerMoney => DealRefusal.notEnoughMoney,
      _ => null,
    };
    if (refusal != null) return DealRefused(refusal);
    return DealDone(
      captorPrisoners: captorPrisoners.without(released),
      ownerPrisoners: ownerPrisoners.without(wanted),
      ransom: ransom,
    );
  }
}

/// {@template exchange_offer}
/// Prisoners for prisoners: the captor releases its prisoners and gets
/// back [wanted], its own units held by the other section.
/// {@endtemplate}
final class ExchangeOffer extends PrisonerOffer {
  /// {@macro exchange_offer}
  const new({
    required super.captorSectionId,
    required super.ownerSectionId,
    required super.released,
    required this.wanted,
  });

  /// The captor section's units the owner releases.
  final List<String> wanted;
}

/// {@template ransom_offer}
/// Prisoners for money: the owner pays [price] to get them back.
/// {@endtemplate}
final class RansomOffer extends PrisonerOffer {
  /// {@macro ransom_offer}
  const new({
    required super.captorSectionId,
    required super.ownerSectionId,
    required super.released,
    required this.price,
  });

  /// The ransom, in whole w€ (decision 200).
  final int price;
}
