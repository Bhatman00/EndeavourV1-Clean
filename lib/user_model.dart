import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String username;
  final String usernameLower;
  final String email;
  final String region;
  final String? photoUrl;
  final bool isPrivate;
  final bool isShadowbanned;
  final int flagCount30d;

  // Gym Stats
  final int bench;
  final int squat;
  final int deadlift;
  final double bodyweight; // in kg
  final String gender; // 'male' or 'female'

  // Elo Points
  final int skillElo;
  final int effortElo;
  final int academicSkillElo;
  final int academicEffortElo;
  final int artSkillElo;
  final int artEffortElo;

  // Art System
  final int critiqueTokens;
  final bool isRankedInArt;
  final List<String> placementArtIds;
  final double artSkillMultiplier;

  final List<String> groupPaths;
  final DateTime? createdAt;

  // Anticheat comparison fields
  final double? prevWilks;
  final int? prevGrade;
  final int? prev5kSeconds;
  final int? prevBaselineHours;
  final int? effortEloAtLastGradeUpdate;
  final int? effortEloAtLastBaselineUpdate;

  UserModel({
    required this.uid,
    required this.username,
    required this.usernameLower,
    required this.email,
    required this.region,
    this.photoUrl,
    this.isPrivate = false,
    this.isShadowbanned = false,
    this.flagCount30d = 0,
    this.bench = 0,
    this.squat = 0,
    this.deadlift = 0,
    this.bodyweight = 0.0,
    this.gender = 'male',
    this.skillElo = 0,
    this.effortElo = 0,
    this.academicSkillElo = 0,
    this.academicEffortElo = 0,
    this.artSkillElo = 0,
    this.artEffortElo = 0,
    this.critiqueTokens = 0,
    this.isRankedInArt = false,
    this.placementArtIds = const [],
    this.artSkillMultiplier = 0.2,
    this.groupPaths = const [],
    this.createdAt,
    this.prevWilks,
    this.prevGrade,
    this.prev5kSeconds,
    this.prevBaselineHours,
    this.effortEloAtLastGradeUpdate,
    this.effortEloAtLastBaselineUpdate,
  });

  // Total Elo Calculations
  int get gymElo => skillElo + effortElo;
  int get academicElo => academicSkillElo + academicEffortElo;
  int get artElo => artSkillElo + artEffortElo;
  int get totalElo => gymElo + academicElo + artElo;

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'usernameLower': usernameLower,
      'email': email,
      'region': region,
      'photoUrl': photoUrl,
      'isPrivate': isPrivate,
      'isShadowbanned': isShadowbanned,
      'flagCount30d': flagCount30d,
      'bench': bench,
      'squat': squat,
      'deadlift': deadlift,
      'bodyweight': bodyweight,
      'gender': gender,
      'skillElo': skillElo,
      'effortElo': effortElo,
      'academicSkillElo': academicSkillElo,
      'academicEffortElo': academicEffortElo,
      'artSkillElo': artSkillElo,
      'artEffortElo': artEffortElo,
      'critiqueTokens': critiqueTokens,
      'isRankedInArt': isRankedInArt,
      'placementArtIds': placementArtIds,
      'artSkillMultiplier': artSkillMultiplier,
      'groupPaths': groupPaths,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      if (prevWilks != null) 'prevWilks': prevWilks,
      if (prevGrade != null) 'prevGrade': prevGrade,
      if (prev5kSeconds != null) 'prev5kSeconds': prev5kSeconds,
      if (prevBaselineHours != null) 'prevBaselineHours': prevBaselineHours,
      if (effortEloAtLastGradeUpdate != null) 'effortEloAtLastGradeUpdate': effortEloAtLastGradeUpdate,
      if (effortEloAtLastBaselineUpdate != null) 'effortEloAtLastBaselineUpdate': effortEloAtLastBaselineUpdate,
    };
  }

  // Create UserModel from Firestore Document
  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      username: map['username'] ?? 'Unknown',
      usernameLower: map['usernameLower'] ?? '',
      email: map['email'] ?? '',
      region: map['region'] ?? 'Unknown',
      photoUrl: map['photoUrl'],
      isPrivate: map['isPrivate'] ?? false,
      isShadowbanned: map['isShadowbanned'] ?? false,
      flagCount30d: (map['flagCount30d'] ?? 0).toInt(),
      bench: (map['bench'] ?? 0).toInt(),
      squat: (map['squat'] ?? 0).toInt(),
      deadlift: (map['deadlift'] ?? 0).toInt(),
      bodyweight: (map['bodyweight'] ?? 0.0).toDouble(),
      gender: map['gender'] ?? 'male',
      skillElo: (map['skillElo'] ?? 0).toInt(),
      effortElo: (map['effortElo'] ?? 0).toInt(),
      academicSkillElo: (map['academicSkillElo'] ?? 0).toInt(),
      academicEffortElo: (map['academicEffortElo'] ?? 0).toInt(),
      artSkillElo: (map['artSkillElo'] ?? 0).toInt(),
      artEffortElo: (map['artEffortElo'] ?? 0).toInt(),
      critiqueTokens: (map['critiqueTokens'] ?? 0).toInt(),
      isRankedInArt: map['isRankedInArt'] ?? false,
      placementArtIds: List<String>.from(map['placementArtIds'] ?? []),
      artSkillMultiplier: (map['artSkillMultiplier'] ?? 0.2).toDouble(),
      groupPaths: List<String>.from(map['groupPaths'] ?? []),
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      prevWilks: (map['prevWilks'] as num?)?.toDouble(),
      prevGrade: (map['prevGrade'] as num?)?.toInt(),
      prev5kSeconds: (map['prev5kSeconds'] as num?)?.toInt(),
      prevBaselineHours: (map['prevBaselineHours'] as num?)?.toInt(),
      effortEloAtLastGradeUpdate: (map['effortEloAtLastGradeUpdate'] as num?)?.toInt(),
      effortEloAtLastBaselineUpdate: (map['effortEloAtLastBaselineUpdate'] as num?)?.toInt(),
    );
  }
}
