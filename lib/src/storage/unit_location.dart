/// {@template unit_location}
/// Where a unit is (HQ-24 to HQ-37, UNIT-29, COMBAT-43): on the field on
/// its own or carried, stored, or a prisoner.
///
/// A State (stack decision 7): each state says what it allows. Only a unit
/// [onField] is seen, attacked and active (UNIT-39, HQ-29); only an
/// [OnField] unit is stored or recalled, and only a [Stored] one deploys
/// (`StorageRules`). A [Prisoner] cannot fight or escape (COMBAT-43).
/// {@endtemplate}
sealed class UnitLocation {
  /// {@macro unit_location}
  const new();

  /// Whether the unit is on the field, carried or not.
  bool get onField;
}

/// {@template on_field}
/// On the field: active, seen and attacked (UNIT-39, HQ-29). A recall in
/// progress ends at [recallDoneAt]; nothing stops it (HQ-32).
/// {@endtemplate}
sealed class OnField extends UnitLocation {
  /// {@macro on_field}
  const new({this.recallDoneAt});

  /// The battle time its recall ends; null when no recall runs.
  final Duration? recallDoneAt;

  @override
  bool get onField => true;

  /// Whether a transport here may take passengers: not while it is
  /// recalled, since a recall cannot stop and a transport is stored empty
  /// (HQ-32, HQ-49, decision 206).
  bool get takesPassengers => recallDoneAt == null;

  /// This unit, recalled until [doneAt].
  OnField recalledUntil(Duration doneAt);

  /// Where the unit is at battle time [now]: stored once its recall is done
  /// (HQ-32), here otherwise. Moves and attacks during the recall change
  /// nothing; a unit that dies during it is simply dead.
  UnitLocation at(Duration now) {
    final doneAt = recallDoneAt;
    return doneAt != null && now >= doneAt ? const Stored() : this;
  }
}

/// {@template deployed}
/// On the field on its own: not carried.
/// {@endtemplate}
final class Deployed extends OnField {
  /// {@macro deployed}
  const new({super.recallDoneAt});

  @override
  Deployed recalledUntil(Duration doneAt) => Deployed(recallDoneAt: doneAt);
}

/// {@template carried}
/// Carried by the transport [transportId]: still on the field (UNIT-29),
/// it takes a share of every hit on the transport (UNIT-37).
/// {@endtemplate}
final class Carried extends OnField {
  /// {@macro carried}
  const new(this.transportId, {super.recallDoneAt});

  /// The carrying transport's unit id.
  final String transportId;

  @override
  Carried recalledUntil(Duration doneAt) =>
      Carried(transportId, recallDoneAt: doneAt);

  /// The unit set down where its transport is, its recall kept: when the
  /// transport is stored by its commander's death (decision 206).
  Deployed setDown() => Deployed(recallDoneAt: recallDoneAt);
}

/// {@template stored}
/// In storage: back in the homeland (HQ-24), never seen nor harmed
/// (HQ-29, UNIT-37). The destruction of the HQ or the guild camp does not
/// affect it (HQ-26, HQ-41). It recovers AP like every unit (HQ-34).
/// {@endtemplate}
final class Stored extends UnitLocation {
  /// {@macro stored}
  const new();

  @override
  bool get onField => false;
}

/// {@template prisoner}
/// A prisoner in the prisoner storage of [captorSectionId] (COMBAT-43). It
/// returns to its owner's storage when released (COMBAT-44).
/// {@endtemplate}
final class Prisoner extends UnitLocation {
  /// {@macro prisoner}
  const new(this.captorSectionId);

  /// The captor section's id.
  final String captorSectionId;

  @override
  bool get onField => false;
}
