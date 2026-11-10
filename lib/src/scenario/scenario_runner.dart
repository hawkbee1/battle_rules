import 'package:battle_rules/src/actions/action_result.dart';
import 'package:battle_rules/src/actions/push.dart';
import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/combat/damage.dart';
import 'package:battle_rules/src/combat/hit_chance.dart';
import 'package:battle_rules/src/combat/seeded_random.dart';
import 'package:battle_rules/src/combat/vec3.dart';
import 'package:battle_rules/src/combat/weapons.dart';
import 'package:battle_rules/src/combat/zero_hp.dart';
import 'package:battle_rules/src/data/game_data.dart';
import 'package:battle_rules/src/data/units_data.dart';
import 'package:battle_rules/src/movement/movement_cost.dart';
import 'package:battle_rules/src/scenario/scenario.dart';
import 'package:battle_rules/src/vision/vision.dart';

/// {@template scenario_summary}
/// What a scenario run adds up to.
/// {@endtemplate}
final class ScenarioSummary {
  /// {@macro scenario_summary}
  const new({
    required this.shots,
    required this.hits,
    required this.damage,
    required this.deaths,
    required this.spared,
    required this.crushed,
    required this.apUsed,
  });

  /// Shots fired.
  final int shots;

  /// Shots that hit (for artillery: that landed on the aimed point).
  final int hits;

  /// HP lost by all units.
  final double damage;

  /// Units killed, the crushed ones included.
  final int deaths;

  /// Units taken prisoner or turned to defectors.
  final int spared;

  /// Units crushed by a relic.
  final int crushed;

  /// AP spent by all units.
  final double apUsed;

  /// The summary as `key=value` pairs.
  String get line =>
      'shots=$shots hits=$hits damage=${damage.toStringAsFixed(2)} '
      'deaths=$deaths spared=$spared crushed=$crushed '
      'ap_used=${apUsed.toStringAsFixed(2)}';
}

/// {@template scenario_report}
/// The result of a scenario run: its [events], its [summary], and when its
/// last event happened.
/// {@endtemplate}
final class ScenarioReport {
  /// {@macro scenario_report}
  const new({
    required this.scenario,
    required this.events,
    required this.summary,
    required this.endsAt,
  });

  /// The scenario played.
  final Scenario scenario;

  /// The event log, one line per event.
  final List<String> events;

  /// The totals.
  final ScenarioSummary summary;

  /// The battle time of the last event.
  final Duration endsAt;

  /// One machine-readable line, so that two runs can be compared (the
  /// performance-test conventions).
  String get machineLine =>
      'scenario="${scenario.name}" seed=${scenario.seed} ${summary.line} '
      'ends_at_s=${_seconds(endsAt)}';

  /// The event log and the summary, for people.
  String get text => [
    'Scenario: ${scenario.name} (seed ${scenario.seed})',
    ...events,
    'Summary: ${summary.line}',
  ].join('\n');
}

/// {@template scenario_runner}
/// Plays scripted scenarios with the rules core (M4 Issue 11): every order
/// goes through the same rules as a battle (AP, weapons, vision, hit
/// chance, damage, 0-HP outcomes, movement, pushing).
///
/// Orders run one after another, in time order: two orders given at the
/// same time are not interleaved.
/// {@endtemplate}
final class ScenarioRunner {
  /// {@macro scenario_runner}
  const new(this.data);

  /// The game data.
  final GameData data;

  /// Plays [scenario].
  ScenarioReport run(Scenario scenario) => _Run(data, scenario).play();
}

/// One unit during a run.
final class _Unit {
  new(this.spec, this.type, this.pool, this.weapon, this.health, this.morale)
    : x = spec.position;

  final ScenarioUnit spec;
  final UnitType type;
  ApPool pool;
  WeaponState weapon;
  Health health;
  final double morale;
  double x;
  bool alive = true;
}

/// The state of one run.
final class _Run {
  new(this.data, this.scenario)
    : random = XorshiftRandom(scenario.seed),
      vision = Vision(data.terrain),
      armory = Armory(data.combat),
      hitChance = HitChance(data.combat),
      damage = Damage(data.combat),
      zeroHp = ZeroHp(rules: data.combat.zeroHp, morale: data.combat.morale),
      movementCost = MovementCost(data.terrain);

  final GameData data;
  final Scenario scenario;
  final SeededRandom random;
  final Vision vision;
  final Armory armory;
  final HitChance hitChance;
  final Damage damage;
  final ZeroHp zeroHp;
  final MovementCost movementCost;

  final _units = <String, _Unit>{};
  final _events = <String>[];
  var _shots = 0;
  var _hits = 0;
  var _damage = 0.0;
  var _deaths = 0;
  var _spared = 0;
  var _crushed = 0;
  var _apUsed = 0.0;
  Duration _last = Duration.zero;

  ScenarioReport play() {
    for (final spec in scenario.units.values) {
      final type =
          data.units.unitTypes[spec.type] ??
          (throw ArgumentError.value(spec.type, 'units.${spec.id}.type'));
      _units[spec.id] = _Unit(
        spec,
        type,
        ApPool.full(
          max: type.stats.apMax,
          recoveryDelayS: data.battle.ap.recoveryDelayS,
          at: Duration.zero,
        ),
        WeaponState.forNewUnit(type, data.combat),
        Health.full(type.stats.hp),
        data.combat.morale.base,
      );
    }
    for (final order in scenario.orders) {
      final at = Duration(
        microseconds: (order.atS * Duration.microsecondsPerSecond).round(),
      );
      switch (order) {
        case FireOrder():
          _fire(order, at);
        case ArtilleryOrder():
          _artillery(order, at);
        case MoveOrder():
          _move(order, at);
        case PushOrder():
          _push(order, at);
      }
    }
    return ScenarioReport(
      scenario: scenario,
      events: List.unmodifiable(_events),
      summary: ScenarioSummary(
        shots: _shots,
        hits: _hits,
        damage: _damage,
        deaths: _deaths,
        spared: _spared,
        crushed: _crushed,
        apUsed: _apUsed,
      ),
      endsAt: _last,
    );
  }

  void _log(Duration at, String event) {
    if (at > _last) _last = at;
    _events.add('t=${_seconds(at)}s $event');
  }

  SightLine _line(double distanceM) =>
      SightLine(distanceM: distanceM, observerTerrain: scenario.terrain);

  /// Fires one shot of [shooter], reloading first when its magazine is
  /// empty; null when the weapon refuses.
  Duration? _shoot(_Unit shooter, Duration now) {
    if (shooter.weapon.loaded && shooter.weapon.rounds == 0) {
      shooter.weapon = (armory.reload(
        state: shooter.weapon,
        pool: shooter.pool,
        now: now,
      ) as WeaponDone).state;
    }
    final result = armory.fire(
      state: shooter.weapon,
      pool: shooter.pool,
      now: now,
    );
    switch (result) {
      case WeaponRefused(:final reason):
        _log(now, '${shooter.spec.id} cannot fire: ${reason.name}');
        return null;
      case WeaponDone(:final at, :final state, :final pool):
        shooter
          ..weapon = state
          ..pool = pool;
        _shots++;
        _apUsed += state.weapon!.apPerShot;
        return at;
    }
  }

  void _fire(FireOrder order, Duration start) {
    final shooter = _units[order.unit]!;
    final target = _units[order.target]!;
    var now = start;
    for (var shot = 0; shot < order.shots; shot++) {
      if (!shooter.alive || !target.alive) return;
      final weapon = shooter.weapon.weapon;
      final distance = (shooter.x - target.x).abs();
      if (weapon == null ||
          !vision.canFireAt(
            unit: shooter.type,
            weapon: weapon,
            weather: scenario.weather,
            line: _line(distance),
            time: now,
          )) {
        _log(now, '${order.unit} cannot fire at ${order.target}');
        return;
      }
      final at = _shoot(shooter, now);
      if (at == null) return;
      now = at;
      final roll = HitChance.roll(
        hitChance.of(
          weapon: weapon,
          attack: shooter.type.stats.attack,
          morale: shooter.morale,
          defense: target.type.stats.defense,
          targetArmor: target.type.armorType,
          targetSpeedMps: 0,
          distanceM: distance,
        ),
        random,
      );
      if (!roll.hits) {
        _log(now, '${order.unit} fires at ${order.target}: miss');
        continue;
      }
      _hits++;
      _hurt(
        shooter,
        target,
        damage.hit(weapon, _targetOf(shooter, target)),
        now,
      );
    }
  }

  void _artillery(ArtilleryOrder order, Duration start) {
    final artillery = _units[order.unit]!;
    final target = _units[order.target]!;
    final weapon = artillery.weapon.weapon!;
    var now = start;
    for (var shot = 0; shot < order.shots; shot++) {
      if (!artillery.alive || !target.alive) return;
      bool sees(_Unit unit) =>
          unit.alive &&
          vision.unitSees(
            unit: unit.type,
            weather: scenario.weather,
            line: _line((unit.x - target.x).abs()),
            time: now,
          );
      final seen = _units.values.any(
        (unit) => unit.spec.section == artillery.spec.section && sees(unit),
      );
      final spotter = order.spotter == null ? null : _units[order.spotter]!;
      final radio = order.radio == null ? null : _units[order.radio]!;
      final relayed =
          spotter != null &&
          radio != null &&
          radio.alive &&
          spotter.type.role.reportsToRadio &&
          sees(spotter) &&
          (radio.x - spotter.x).abs() <= (radio.type.role.relayRange ?? 0);
      final distance = (artillery.x - target.x).abs();
      if (!HitChance.canTargetPosition(
        weapon: weapon,
        distanceM: distance,
        seenBySection: seen,
        relayedByRadio: relayed,
      )) {
        _log(now, '${order.unit} cannot target ${order.target}');
        return;
      }
      final at = _shoot(artillery, now);
      if (at == null) return;
      now = at;
      final roll = HitChance.roll(
        hitChance.of(
          weapon: weapon,
          attack: artillery.type.stats.attack,
          morale: artillery.morale,
          defense: target.type.stats.defense,
          targetArmor: target.type.armorType,
          targetSpeedMps: 0,
          distanceM: distance,
        ),
        random,
      );
      final landed = hitChance.landingPoint(
        weapon: weapon,
        artillery: Vec3(artillery.x, 0, 0),
        aimed: Vec3(target.x, 0, 0),
        roll: roll,
        random: random,
      );
      if (roll.hits) _hits++;
      final off = (landed - Vec3(target.x, 0, 0)).length;
      _log(
        now,
        '${order.unit} shells ${order.target}: '
        '${roll.hits ? 'on target' : 'lands ${off.toStringAsFixed(1)} m off'}',
      );
      for (final unit in _units.values.where((unit) => unit.alive)) {
        final distanceToImpact = (Vec3(unit.x, 0, 0) - landed).length;
        final amount = damage.splash(
          weapon,
          _targetOf(artillery, unit),
          distanceToImpact,
        );
        if (amount > 0) _hurt(artillery, unit, amount, now);
      }
    }
  }

  void _move(MoveOrder order, Duration start) {
    final unit = _units[order.unit]!;
    if (!unit.weapon.canMoveAt(start)) {
      _log(start, '${order.unit} cannot move: its weapon is loaded');
      return;
    }
    final mover = Mover.unit(unit.type, flying: unit.spec.flying);
    final cost = movementCost.ofPath(mover, order.path);
    final movement = movementCost.move(
      mover: mover,
      pool: unit.pool,
      start: start,
      path: order.path,
    );
    if (cost == null || movement == null) {
      _log(start, '${order.unit} cannot move: impassable');
      return;
    }
    final length = order.path.fold<double>(
      0,
      (sum, sample) => sum + sample.lengthM,
    );
    unit
      ..pool = movement.pool
      ..x += length;
    _apUsed += cost;
    _log(
      movement.arrivesAt,
      '${order.unit} moves ${length.toStringAsFixed(1)} m for '
      '${cost.toStringAsFixed(2)} AP',
    );
  }

  void _push(PushOrder order, Duration start) {
    final pushing = PushingRules(push: data.combat.push, cost: movementCost);
    var pot = PushPot(owner: order.owner);
    var startPush = start;
    var pushers = 0;
    for (final id in order.pushers) {
      final pusher = _units[id]!;
      var pushes = false;
      for (var turn = 0; turn < order.contributions; turn++) {
        final result = pushing.contribute(
          unit: pusher.type,
          team: pusher.spec.team,
          pot: pot,
          pool: pusher.pool,
          now: start,
        );
        if (result is! PushContributed) {
          _log(start, '$id cannot push');
          break;
        }
        pushes = true;
        pot = result.pot;
        pusher.pool = result.pool;
        _apUsed += data.combat.push.contributionAp;
        if (result.at > startPush) startPush = result.at;
      }
      if (pushes) pushers++;
    }
    final inPath = order.inPath.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final move = pushing.move(
      pot: pot,
      pushers: pushers,
      path: order.path,
      start: startPush,
      unitsInPathAtM: [for (final entry in inPath) entry.value],
    );
    for (final entry in inPath.take(move.crushed)) {
      _units[entry.key]!.alive = false;
      _deaths++;
      _crushed++;
      _log(move.endsAt, '${entry.key} is crushed');
    }
    _log(
      move.endsAt,
      'the relic moves ${move.distanceM.toStringAsFixed(1)} m with $pushers '
      'pushers and stops: ${move.stop.name}, '
      '${move.pot.ap.toStringAsFixed(1)} AP left in its pot',
    );
  }

  DamageTarget _targetOf(_Unit attacker, _Unit target) => DamageTarget(
    armorType: target.type.armorType,
    flying: target.spec.flying,
    friendly: target.spec.team == attacker.spec.team,
  );

  void _hurt(_Unit attacker, _Unit target, double amount, Duration now) {
    final before = target.health.current;
    target.health = target.health.damaged(amount);
    final lost = before - target.health.current;
    _damage += lost;
    _log(
      now,
      '${attacker.spec.id} hits ${target.spec.id} for '
      '${lost.toStringAsFixed(2)} HP',
    );
    if (!target.health.isZero) return;
    target.alive = false;
    final outcome = zeroHp.resolve(
      attacker: attacker.type,
      target: target.type,
      targetIsEnemy: target.spec.team != attacker.spec.team,
      moraleValue: target.morale,
      ap: target.pool.apAt(now),
      attackerSectionHasRoom: true,
      random: random,
    );
    if (outcome == ZeroHpOutcome.death) {
      _deaths++;
    } else {
      _spared++;
    }
    _log(now, '${target.spec.id} is at 0 HP: ${outcome.name}');
  }
}

String _seconds(Duration time) =>
    (time.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(1);
