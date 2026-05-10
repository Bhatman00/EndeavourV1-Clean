import 'package:flutter/material.dart';

class Rank {
  final String name;
  final Color color;
  final int threshold;

  const Rank({
    required this.name,
    required this.color,
    required this.threshold,
  });
}

class RankUtils {
  // ═══════════════════════════════════════════════════════════════════════
  //  Standard 6-Tier Video Game Rank System
  //  -------------------------------------------------------------------
  //  Every endeavour (gym, academic, art, lumina, running) now shares the
  //  same 6 canonical ranks with identical names, thresholds and rank
  //  colors.  Dashboards pass their own accent color to the painter, so
  //  each endeavour still feels distinct — but rank progression is
  //  uniform and immediately understandable.
  // ═══════════════════════════════════════════════════════════════════════

  static const List<Rank> _standardRanks = [
    Rank(name: "BRONZE",      color: Color(0xFFCD7F32), threshold: 0),
    Rank(name: "SILVER",      color: Color(0xFFC0C0C0), threshold: 500),
    Rank(name: "GOLD",        color: Color(0xFFFFD700), threshold: 1500),
    Rank(name: "PLATINUM",    color: Color(0xFFB0E0FF), threshold: 3500),
    Rank(name: "DIAMOND",     color: Color(0xFF00E5FF), threshold: 7000),
    Rank(name: "ENLIGHTENED", color: Color(0xFFE040FB), threshold: 12000),
  ];

  static const List<Rank> gymRanks      = _standardRanks;
  static const List<Rank> academicRanks = _standardRanks;
  static const List<Rank> artRanks      = _standardRanks;
  static const List<Rank> luminaRanks   = _standardRanks;
  static const List<Rank> runningRanks  = _standardRanks;

  static Rank getRank(int elo, List<Rank> ranks) {
    return ranks.lastWhere(
      (r) => elo >= r.threshold,
      orElse: () => ranks.first,
    );
  }

  static String formatElo(int elo) {
    if (elo < 1000) return elo.toString();
    if (elo < 1000000) {
      return '${(elo / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
    }
    if (elo < 1000000000) {
      return '${(elo / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
    }
    return '${(elo / 1000000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}B';
  }

  /// Progress toward the next rank as a value in [0, 1].
  static double rankProgress(int elo, List<Rank> ranks) {
    final rank = getRank(elo, ranks);
    final idx = ranks.indexOf(rank);
    if (idx >= ranks.length - 1) return 1.0;
    final curr = rank.threshold;
    final next = ranks[idx + 1].threshold;
    if (next <= curr) return 1.0;
    return ((elo - curr) / (next - curr)).clamp(0.0, 1.0);
  }

  /// Returns the next rank, or null if already at the max rank.
  static Rank? nextRank(int elo, List<Rank> ranks) {
    final rank = getRank(elo, ranks);
    final idx = ranks.indexOf(rank);
    if (idx >= ranks.length - 1) return null;
    return ranks[idx + 1];
  }

  /// ELO remaining to the next rank (0 if maxed out).
  static int eloToNext(int elo, List<Rank> ranks) {
    final next = nextRank(elo, ranks);
    if (next == null) return 0;
    return (next.threshold - elo).clamp(0, 1 << 30);
  }

  static String getRankImage(Rank rank, List<Rank> ranks, String prefix, int maxImages) {
    final index = ranks.indexOf(rank);
    final imageNumber = (index + 1).clamp(1, maxImages);
    return 'images/$prefix$imageNumber.png';
  }

  static String getGymRankImage(Rank rank) => getRankImage(rank, gymRanks, 'gymrank', 5);
  static String getAcademicRankImage(Rank rank) => getRankImage(rank, academicRanks, 'academicrank', 5);
  static String getRunningRankImage(Rank rank) => getRankImage(rank, runningRanks, 'runrank', 5);
  static String getLuminaRankImage(Rank rank) => getRankImage(rank, luminaRanks, 'luminaryrank', 5);
}
