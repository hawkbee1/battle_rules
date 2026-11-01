import 'package:battle_rules/src/data/data_reader.dart';

/// The name of the economy data file in messages.
const economyFile = 'economy.yaml';

/// {@template economy_data}
/// The `economy.yaml` game data file: currency, prices, earnings and
/// transfer fees (decision 112).
/// {@endtemplate}
final class EconomyData {
  /// {@macro economy_data}
  const new({
    required this.version,
    required this.currency,
    required this.minStartingMoney,
    required this.defaultPrice,
    required this.prices,
    required this.earnings,
    required this.transferFeeInsideGuild,
    required this.transferFeeOutsideGuild,
    required this.xpPurchasable,
    required this.buildDestroyFarmingLimit,
  });

  /// Parses the text of `economy.yaml`.
  factory parse(String text) {
    final reader = DataReader.parse(economyFile, text);
    final prices = reader.map('prices');
    final earnings = reader.map('earnings');
    final fees = reader.map('transfer_fees');
    return EconomyData(
      version: reader.integer('version'),
      currency: reader.string('currency'),
      minStartingMoney: reader.map('war_defaults').number('min_starting_money'),
      defaultPrice: prices.number('default'),
      prices: Map.unmodifiable({
        for (final key in prices.keys)
          if (key != 'default') key: prices.number(key),
      }),
      earnings: Earnings(
        hit: earnings.number('hit'),
        kill: earnings.number('kill'),
        construction: earnings.number('construction'),
        heal: earnings.number('heal'),
        hqHit: earnings.number('hq_hit'),
        hqDestruction: earnings.number('hq_destruction'),
      ),
      transferFeeInsideGuild: fees.number('inside_guild'),
      transferFeeOutsideGuild: fees.number('outside_guild'),
      xpPurchasable: reader.boolean('xp_purchasable'),
      buildDestroyFarmingLimit: reader.string('build_destroy_farming_limit'),
    );
  }

  /// The file's `version`.
  final int version;

  /// The currency.
  final String currency;

  /// Least money of a section; also a new section's money (decision 102).
  final double minStartingMoney;

  /// Price of anything not listed in [prices].
  final double defaultPrice;

  /// Listed prices, by item.
  final Map<String, double> prices;

  /// Money earned by the acting unit's section.
  final Earnings earnings;

  /// Fee on a transfer inside a guild.
  final double transferFeeInsideGuild;

  /// Fee on a transfer outside a guild.
  final double transferFeeOutsideGuild;

  /// Whether XP can be bought.
  final bool xpPurchasable;

  /// Limit on build-and-destroy farming, for example `none`.
  final String buildDestroyFarmingLimit;

  /// The price of [item]: its listed price, else [defaultPrice].
  double priceOf(String item) => prices[item] ?? defaultPrice;
}

/// {@template earnings}
/// Money earned by the acting unit's section (`earnings`).
/// {@endtemplate}
final class Earnings {
  /// {@macro earnings}
  const new({
    required this.hit,
    required this.kill,
    required this.construction,
    required this.heal,
    required this.hqHit,
    required this.hqDestruction,
  });

  /// Per hit.
  final double hit;

  /// Per kill.
  final double kill;

  /// Per construction.
  final double construction;

  /// Per heal.
  final double heal;

  /// Per hit on an HQ.
  final double hqHit;

  /// Per HQ destroyed.
  final double hqDestruction;
}
