import 'package:battle_rules/src/data/units_data.dart';
import 'package:battle_rules/src/progression/section_level.dart';

/// A section's role in its guild (SOC-50, decision 146).
enum GuildRole {
  /// The creator, or whom he handed the role to (SOC-46).
  chief,

  /// A section the chief accepted.
  member,

  /// A new section the chief has not accepted yet.
  trainee,
}

/// Why a guild action is refused.
enum GuildRefusal {
  /// The section is in a guild already.
  alreadyInGuild,

  /// Its commander is below `guild_creation_min_level` (SOC-53).
  levelTooLow,

  /// The guild is in another team of the battle: a guild's sections stay
  /// together (SOC-20).
  otherTeam,

  /// The guild is at its size, trainees included (SOC-47, decision 213).
  guildFull,

  /// Only the chief does that.
  notChief,

  /// The section is not a trainee of the guild.
  notTrainee,

  /// The section is not a member of the guild.
  notMember,

  /// The section is not in the guild.
  notInGuild,

  /// The chief cannot leave while he is chief (SOC-46).
  chiefCannotLeave,
}

/// The outcome of a guild action.
sealed class GuildChange {
  const new();
}

/// {@template guild_changed}
/// The guild is now [guild]; null once disbanded.
/// {@endtemplate}
final class GuildChanged extends GuildChange {
  /// {@macro guild_changed}
  const new(this.guild);

  /// The guild after the action; null once disbanded.
  final Guild? guild;
}

/// {@template guild_refused}
/// Nothing changes, for [reason].
/// {@endtemplate}
final class GuildRefused extends GuildChange {
  /// {@macro guild_refused}
  const new(this.reason);

  /// Why.
  final GuildRefusal reason;
}

/// {@template guild}
/// A guild of a war (decision 108): its sections' [roles], the [xp] they
/// earned while in it, and whether it is on the newcomer list
/// ([optedIn], SOC-03). It can have a single section (SOC-48). Its chats
/// are on Discord (SOC-51). Its camp is a unit of the chief's section
/// (HQ-47).
/// {@endtemplate}
final class Guild {
  /// {@macro guild}
  const new({
    required this.id,
    required this.roles,
    this.xp = 0,
    this.optedIn = false,
  });

  /// The guild's id.
  final String id;

  /// Each section's role, by section id.
  final Map<String, GuildRole> roles;

  /// The XP its sections' units earned while in it (SOC-47; assumed,
  /// Q-SOC-18).
  final double xp;

  /// Whether it accepts newcomers (SOC-03, SOC-08).
  final bool optedIn;

  /// The chief's section id.
  String get chief =>
      roles.entries.firstWhere((role) => role.value == GuildRole.chief).key;

  Guild _with({Map<String, GuildRole>? roles, double? xp, bool? optedIn}) =>
      Guild(
        id: id,
        roles: roles ?? this.roles,
        xp: xp ?? this.xp,
        optedIn: optedIn ?? this.optedIn,
      );
}

/// {@template guild_rules}
/// Guilds (SOC-46 to SOC-53, decisions 108, 146, 153, 155, 213 to 215),
/// from `units.yaml` `progression`: `guild_creation_min_level`,
/// `guild_size` and the `commander_levels` curve (assumed, Q-SOC-18).
///
/// A section without a guild plays on and stores its units at the HQ
/// (SOC-49, `StorageRules.placeOf`).
/// {@endtemplate}
final class GuildRules {
  /// {@macro guild_rules}
  const new(this.progression);

  /// The `progression` of `units.yaml`.
  final Progression progression;

  /// The guild's level, read on the `commander_levels` curve from its XP
  /// (assumed, Q-SOC-18).
  int levelOf(Guild guild) => SectionLevel(progression).levelFor(guild.xp);

  /// The sections [guild] holds at its level, trainees included (SOC-47,
  /// decision 213).
  int maxSections(Guild guild) =>
      progression.guildSize.sectionsAt(levelOf(guild));

  /// Whether [guild] has room for one more section. A full guild takes no
  /// trainee and is not offered to newcomers (decision 213).
  bool hasRoom(Guild guild) => guild.roles.length < maxSections(guild);

  /// The section [sectionId] creates the guild [guildId] and is its chief
  /// (SOC-46, SOC-53, decision 155): it is in no guild ([inGuild]) and its
  /// commander is at `guild_creation_min_level` ([commanderLevel]).
  GuildChange create({
    required String guildId,
    required String sectionId,
    required bool inGuild,
    required int commanderLevel,
  }) {
    if (inGuild) return const GuildRefused(GuildRefusal.alreadyInGuild);
    if (commanderLevel < progression.guildCreationMinLevel) {
      return const GuildRefused(GuildRefusal.levelTooLow);
    }
    return GuildChanged(
      Guild(id: guildId, roles: Map.unmodifiable({sectionId: GuildRole.chief})),
    );
  }

  /// The section [sectionId], in no guild ([inGuild]), joins [guild] as a
  /// trainee (SOC-03, SOC-52, decision 129): a guild of its team in the
  /// battle running ([sameTeam]; true between battles), with room.
  GuildChange apply(
    Guild guild, {
    required String sectionId,
    required bool inGuild,
    required bool sameTeam,
  }) {
    if (inGuild) return const GuildRefused(GuildRefusal.alreadyInGuild);
    if (!sameTeam) return const GuildRefused(GuildRefusal.otherTeam);
    if (!hasRoom(guild)) return const GuildRefused(GuildRefusal.guildFull);
    return GuildChanged(
      guild._with(
        roles: Map.unmodifiable({...guild.roles, sectionId: GuildRole.trainee}),
      ),
    );
  }

  /// The chief ([by]) accepts the trainee [trainee]: it becomes a member
  /// (SOC-50).
  GuildChange accept(
    Guild guild, {
    required String by,
    required String trainee,
  }) => _decide(guild, by: by, trainee: trainee, accepted: true);

  /// The chief ([by]) refuses the trainee [trainee]: it leaves the guild,
  /// nothing else happens to it, and it can apply to another (SOC-52,
  /// decision 153).
  GuildChange refuse(
    Guild guild, {
    required String by,
    required String trainee,
  }) => _decide(guild, by: by, trainee: trainee, accepted: false);

  /// The member or trainee [sectionId] leaves [guild]. The chief cannot
  /// (SOC-46).
  GuildChange leave(Guild guild, {required String sectionId}) =>
      switch (guild.roles[sectionId]) {
        null => const GuildRefused(GuildRefusal.notInGuild),
        GuildRole.chief => const GuildRefused(GuildRefusal.chiefCannotLeave),
        _ => GuildChanged(
          guild._with(
            roles: Map.unmodifiable({...guild.roles}..remove(sectionId)),
          ),
        ),
      };

  /// The chief ([by]) hands his role to the member [to] and becomes a
  /// member (SOC-46). The guild camp passes to the new chief's section
  /// (HQ-47, decision 214).
  GuildChange handOver(Guild guild, {required String by, required String to}) {
    if (guild.roles[by] != GuildRole.chief) {
      return const GuildRefused(GuildRefusal.notChief);
    }
    if (guild.roles[to] != GuildRole.member) {
      return const GuildRefused(GuildRefusal.notMember);
    }
    return GuildChanged(
      guild._with(
        roles: Map.unmodifiable({
          ...guild.roles,
          by: GuildRole.member,
          to: GuildRole.chief,
        }),
      ),
    );
  }

  /// The chief ([by]) disbands [guild]: its sections have no guild and
  /// store at the HQ; its camp is destroyed (SOC-46, decision 214).
  GuildChange disband(Guild guild, {required String by}) =>
      guild.roles[by] == GuildRole.chief
      ? const GuildChanged(null)
      : const GuildRefused(GuildRefusal.notChief);

  /// The chief ([by]) puts [guild] on the newcomer list or takes it off,
  /// at any time, with no reward or penalty (SOC-08, decisions 101, 215).
  GuildChange optIn(Guild guild, {required String by, required bool optedIn}) =>
      guild.roles[by] == GuildRole.chief
      ? GuildChanged(guild._with(optedIn: optedIn))
      : const GuildRefused(GuildRefusal.notChief);

  /// [guild] after one of its sections' units earned [xp] (SOC-47; assumed,
  /// Q-SOC-18): every XP point counts, trainees' included.
  Guild earned(Guild guild, double xp) => guild._with(xp: guild.xp + xp);

  GuildChange _decide(
    Guild guild, {
    required String by,
    required String trainee,
    required bool accepted,
  }) {
    if (guild.roles[by] != GuildRole.chief) {
      return const GuildRefused(GuildRefusal.notChief);
    }
    if (guild.roles[trainee] != GuildRole.trainee) {
      return const GuildRefused(GuildRefusal.notTrainee);
    }
    final roles = {...guild.roles};
    if (accepted) {
      roles[trainee] = GuildRole.member;
    } else {
      roles.remove(trainee);
    }
    return GuildChanged(guild._with(roles: Map.unmodifiable(roles)));
  }
}
