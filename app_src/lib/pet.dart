import 'dart:math';

enum PetStage { egg, baby, beast, saint, god }
enum PetBranch { guardian, wisdom, speed }
enum GiftType { exp, energy, food }

class GiftResult {
  final GiftType type;
  final int amount;
  final String title;
  const GiftResult(this.type, this.amount, this.title);
}

class PetState {
  int exp;
  int energy;
  int food;
  PetStage stage;
  PetBranch branch;

  PetState({
    required this.exp,
    required this.energy,
    required this.food,
    required this.stage,
    required this.branch,
  });

  factory PetState.initial() => PetState(
        exp: 0,
        energy: 100,
        food: 0,
        stage: PetStage.egg,
        branch: PetBranch.wisdom,
      );

  Map<String, dynamic> toJson() => {
        "exp": exp,
        "energy": energy,
        "food": food,
        "stage": stage.index,
        "branch": branch.index,
      };

  static PetState fromJson(Map<String, dynamic> j) => PetState(
        exp: (j["exp"] ?? 0) as int,
        energy: (j["energy"] ?? 100) as int,
        food: (j["food"] ?? 0) as int,
        stage: PetStage.values[(j["stage"] ?? 0) as int],
        branch: PetBranch.values[(j["branch"] ?? 1) as int],
      );

  void addExp(int v) {
    exp += v;
    _recalcStage();
  }

  void addEnergy(int v) {
    energy = max(0, min(200, energy + v));
  }

  void addFood(int v) {
    food = max(0, min(9999, food + v));
  }

  void _recalcStage() {
    // mốc exp đơn giản, bạn thích đổi mốc nào cũng được
    if (exp >= 5000) stage = PetStage.god;
    else if (exp >= 2500) stage = PetStage.saint;
    else if (exp >= 1000) stage = PetStage.beast;
    else if (exp >= 200) stage = PetStage.baby;
    else stage = PetStage.egg;
  }
}
