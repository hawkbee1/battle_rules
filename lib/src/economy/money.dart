import 'dart:math' as math;

import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/economy_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// `purchasable_by` of a unit only the guild chief buys: the guild camp.
const guildChiefBuyer = 'guild_commander';

/// `purchasable_by` of a unit the section's commander buys; also what a type
/// without `purchasable_by` means.
const commanderBuyer = 'commander';

/// Fees are computed in basis points so that halves round exactly.
const _basisPoints = 10000;

/// What earns a section money (ECO-02, ECO-03, ECO-18, HQ-04). A shot
/// that kills earns its hit and its kill: two events (decision 201).
sealed class Earning {
  const new();
}

/// {@template hit_earning}
/// A successful hit on a unit. On an ally it earns nothing (decision 202).
/// {@endtemplate}
final class HitEarning extends Earning {
  /// {@macro hit_earning}
  const new({this.ally = false});

  /// Whether the target is on the shooter's team.
  final bool ally;
}

/// {@template kill_earning}
/// A unit killed. Only an enemy's death earns (ECO-02).
/// {@endtemplate}
final class KillEarning extends Earning {
  /// {@macro kill_earning}
  const new({this.ally = false});

  /// Whether the unit killed was on the killer's team.
  final bool ally;
}

/// {@template hq_hit_earning}
/// A hit on an HQ. Only an enemy HQ earns (ECO-02, decision 202).
/// {@endtemplate}
final class HqHitEarning extends Earning {
  /// {@macro hq_hit_earning}
  const new({this.own = false});

  /// Whether it is the shooter's own HQ.
  final bool own;
}

/// {@template hq_destroyed_earning}
/// An HQ destroyed. Only an enemy HQ earns (HQ-04).
/// {@endtemplate}
final class HqDestroyedEarning extends Earning {
  /// {@macro hq_destroyed_earning}
  const new({this.own = false});

  /// Whether it was the shooter's own HQ.
  final bool own;
}

/// {@template construction_earning}
/// An engineer's construction completed: it earns every time, with no
/// limit on building and destroying (ECO-15, ECO-22).
/// {@endtemplate}
final class ConstructionEarning extends Earning {
  /// {@macro construction_earning}
  const new();
}

/// {@template heal_earning}
/// A heal by [healer]: it earns when the healer's role says so (ECO-03,
/// decision 145).
/// {@endtemplate}
final class HealEarning extends Earning {
  /// {@macro heal_earning}
  const new(this.healer);

  /// The healing unit's type.
  final UnitType healer;
}

/// Why a purchase is refused.
enum PurchaseRefusal {
  /// A commander comes with his section and is never bought (UNIT-41).
  notForSale,

  /// Only the guild chief buys the guild camp (ECO-06).
  notGuildChief,

  /// The guild already has its camp (HQ-42).
  campExists,

  /// The section has no free room for one more unit (ECO-04, decision 130).
  noRoom,

  /// The section is under its 24-hour lock: a bought unit would arrive on
  /// the field (HQ-35, decision 205).
  sectionLocked,

  /// An enemy near the section's portal blocks the unit's arrival (HQ-46,
  /// decision 205).
  arrivalBlocked,

  /// The section's money does not pay the price.
  notEnoughMoney,
}

/// The outcome of a purchase.
sealed class Purchase {
  const new();
}

/// {@template bought}
/// Bought for [price]; the section has [moneyLeft].
/// {@endtemplate}
final class Bought extends Purchase {
  /// {@macro bought}
  const new({required this.price, required this.moneyLeft});

  /// What it cost.
  final int price;

  /// The section's money after paying.
  final int moneyLeft;
}

/// {@template purchase_refused}
/// Not bought, for [reason]; nothing changes.
/// {@endtemplate}
final class PurchaseRefused extends Purchase {
  /// {@macro purchase_refused}
  const new(this.reason);

  /// Why.
  final PurchaseRefusal reason;
}

/// Why a transfer is refused.
enum TransferRefusal {
  /// Money moves only between sections of one team (ECO-10).
  otherTeam,

  /// Nothing to send.
  notPositive,

  /// The sender has less than the amount.
  notEnoughMoney,
}

/// The outcome of a transfer.
sealed class Transfer {
  const new();
}

/// {@template transferred}
/// The sender paid the amount; the receiver got [received]; [fee] was
/// destroyed (ECO-11).
/// {@endtemplate}
final class Transferred extends Transfer {
  /// {@macro transferred}
  const new({required this.received, required this.fee});

  /// What reaches the receiver.
  final int received;

  /// What the transfer destroyed.
  final int fee;
}

/// {@template transfer_refused}
/// No money moves, for [reason].
/// {@endtemplate}
final class TransferRefused extends Transfer {
  /// {@macro transfer_refused}
  const new(this.reason);

  /// Why.
  final TransferRefusal reason;
}

/// {@template money_rules}
/// A section's money (ECO-01 to ECO-22, SOC-10 to SOC-15), from
/// `economy.yaml`. Money belongs to the section, in whole w€
/// (decision 200); there is no team or guild treasury.
/// {@endtemplate}
final class MoneyRules {
  /// {@macro money_rules}
  const new(this.economy);

  /// The `economy.yaml` data.
  final EconomyData economy;

  /// The money [earning] gives the acting unit's section (ECO-18).
  int earned(Earning earning) {
    final rates = economy.earnings;
    return switch (earning) {
      HitEarning(:final ally) => ally ? 0 : rates.hit,
      KillEarning(:final ally) => ally ? 0 : rates.kill,
      HqHitEarning(:final own) => own ? 0 : rates.hqHit,
      HqDestroyedEarning(:final own) => own ? 0 : rates.hqDestruction,
      ConstructionEarning() => rates.construction,
      HealEarning(:final healer) =>
        healer.role.earnsMoneyWhenHealing ? rates.heal : 0,
    };
  }

  /// A section with [money] buys a unit of [type] (ECO-04 to ECO-06,
  /// UNIT-27, HQ-42, HQ-43). The guild camp is bought by the guild chief
  /// ([guildChief]) when his guild has none ([guildHasCamp]); it counts in
  /// no cap. Any other unit is bought by the section's commander and needs
  /// free room ([hasRoom], from `SectionLevel.hasRoom`).
  ///
  /// The unit arrives next to the section's portal (ECO-07, HQ-46,
  /// `StorageRules.placeOf`): nothing is bought while the section is
  /// [locked] or an enemy blocks the arrival ([arrivalBlocked], from
  /// `StorageRules.blocks`) (decision 205).
  Purchase buyUnit({
    required UnitType type,
    required int money,
    required bool hasRoom,
    required bool locked,
    required bool arrivalBlocked,
    bool guildChief = false,
    bool guildHasCamp = false,
  }) {
    final price = economy.priceOf(type.id);
    final camp = type.purchasableBy == guildChiefBuyer;
    final refusal = switch (type) {
      _ when type.category == 'commander' => PurchaseRefusal.notForSale,
      _ when camp && !guildChief => PurchaseRefusal.notGuildChief,
      _ when camp && guildHasCamp => PurchaseRefusal.campExists,
      _ when type.countsInSectionCap && !hasRoom => PurchaseRefusal.noRoom,
      _ when locked => PurchaseRefusal.sectionLocked,
      _ when arrivalBlocked => PurchaseRefusal.arrivalBlocked,
      _ when price > money => PurchaseRefusal.notEnoughMoney,
      _ => null,
    };
    return refusal == null
        ? Bought(price: price, moneyLeft: money - price)
        : PurchaseRefused(refusal);
  }

  /// A section with [money] buys [weapon]; it goes to the section's storage
  /// (COMBAT-27, decision 151) and needs no room.
  Purchase buyWeapon({required WeaponType weapon, required int money}) {
    final price = economy.priceOf(weapon.id);
    return price > money
        ? const PurchaseRefused(PurchaseRefusal.notEnoughMoney)
        : Bought(price: price, moneyLeft: money - price);
  }

  /// A section with [senderMoney] sends [amount] to another section
  /// (ECO-08 to ECO-11, ECO-19): of one team only; the fee, `inside_guild`
  /// between sections of one guild ([sameGuild]) or `outside_guild`, is
  /// taken from the amount (decision 203), rounded to the nearest whole w€,
  /// halves up (decision 200), and destroyed.
  Transfer transfer({
    required int amount,
    required int senderMoney,
    required bool sameTeam,
    required bool sameGuild,
  }) {
    if (!sameTeam) return const TransferRefused(TransferRefusal.otherTeam);
    if (amount <= 0) return const TransferRefused(TransferRefusal.notPositive);
    if (amount > senderMoney) {
      return const TransferRefused(TransferRefusal.notEnoughMoney);
    }
    final rate = sameGuild
        ? economy.transferFeeInsideGuild
        : economy.transferFeeOutsideGuild;
    final rateBp = (rate * _basisPoints).round();
    final fee = (amount * rateBp + _basisPoints ~/ 2) ~/ _basisPoints;
    return Transferred(received: amount - fee, fee: fee);
  }

  /// A new section's money: its war's `minStartingMoney` (SOC-15, UNIT-41).
  int startingMoney(int warMinStartingMoney) => warMinStartingMoney;

  /// The money of a section with [money] after its commander dies:
  /// `max(money, war minStartingMoney)` (SOC-10, ECO-13).
  int afterCommanderDeath(int money, {required int warMinStartingMoney}) =>
      math.max(money, warMinStartingMoney);

  /// The money of a section with [money] after it loses a unit and has
  /// [unitsLeft] besides its commander: the safety net of
  /// [afterCommanderDeath] once none is left (SOC-10, ECO-13).
  int afterUnitLost(
    int money, {
    required int unitsLeft,
    required int warMinStartingMoney,
  }) => unitsLeft == 0
      ? afterCommanderDeath(money, warMinStartingMoney: warMinStartingMoney)
      : money;
}
