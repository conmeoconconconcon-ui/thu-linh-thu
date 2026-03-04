import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum PetStage { egg, baby, beast, saint, god }
enum PetBranch { guardian, wisdom, speed }

class PetState {
  int level;
  int exp;
  int energy;
  int food;
  PetStage stage;
  PetBranch branch;

  int pagesTurnedToday;
  int readSecondsToday;

  PetState({
    required this.level,
    required this.exp,
    required this.energy,
    required this.food,
    required this.stage,
    required this.branch,
    required this.pagesTurnedToday,
    required this.readSecondsToday,
  });

  factory PetState.initial() => PetState(
        level: 1,
        exp: 0,
        energy: 0,
        food: 0,
        stage: PetStage.egg,
        branch: PetBranch.wisdom,
        pagesTurnedToday: 0,
        readSecondsToday: 0,
      );

  int get expToNext => 80 + (level * 25);

  void addExp(int amount) {
    exp += amount;
    while (exp >= expToNext) {
      exp -= expToNext;
      level += 1;
    }
  }

  bool canEvolve() => switch (stage) {
        PetStage.egg => level >= 3 && food >= 2,
        PetStage.baby => level >= 8 && food >= 5,
        PetStage.beast => level >= 15 && food >= 10,
        PetStage.saint => level >= 25 && food >= 20,
        PetStage.god => false,
      };

  void evolve() {
    if (!canEvolve()) return;
    switch (stage) {
      case PetStage.egg:
        food -= 2;
        stage = PetStage.baby;
        break;
      case PetStage.baby:
        food -= 5;
        stage = PetStage.beast;
        break;
      case PetStage.beast:
        food -= 10;
        stage = PetStage.saint;
        break;
      case PetStage.saint:
        food -= 20;
        stage = PetStage.god;
        break;
      case PetStage.god:
        break;
    }
  }

  Map<String, dynamic> toJson() => {
        "level": level,
        "exp": exp,
        "energy": energy,
        "food": food,
        "stage": stage.index,
        "branch": branch.index,
        "pagesTurnedToday": pagesTurnedToday,
        "readSecondsToday": readSecondsToday,
      };

  static PetState fromJson(Map<String, dynamic> j) => PetState(
        level: j["level"],
        exp: j["exp"],
        energy: j["energy"],
        food: j["food"],
        stage: PetStage.values[j["stage"]],
        branch: PetBranch.values[j["branch"]],
        pagesTurnedToday: j["pagesTurnedToday"] ?? 0,
        readSecondsToday: j["readSecondsToday"] ?? 0,
      );
}

class PetStore {
  static const _key = "pet_state_v1";

  static Future<PetState> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return PetState.initial();
    return PetState.fromJson(jsonDecode(raw));
  }

  static Future<void> save(PetState s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(s.toJson()));
  }
}
