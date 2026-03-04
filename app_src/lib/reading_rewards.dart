import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'pet.dart';

class ReadingRewards {
  static const _kLastActive = "last_active_reading_ms";
  static const _kTickCounter = "tick_counter_10s";

  // gọi khi user đang đọc (để app biết user có "hoạt động")
  static Future<void> markUserActiveReading() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastActive, DateTime.now().millisecondsSinceEpoch);
  }

  // mỗi 10 giây đọc -> cộng EXP + thỉnh thoảng có quà
  static Future<GiftResult?> tick10s(PetState pet) async {
    final prefs = await SharedPreferences.getInstance();

    final last = prefs.getInt(_kLastActive) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // nếu user bỏ app lâu thì không thưởng
    if (now - last > 15 * 1000) return null;

    // thưởng EXP theo nhánh
    final baseExp = switch (pet.branch) {
      PetBranch.wisdom => 8,
      PetBranch.guardian => 6,
      PetBranch.speed => 10,
    };

    pet.addExp(baseExp);
    pet.addEnergy(-1);

    // đếm tick để thỉnh thoảng quà
    int c = (prefs.getInt(_kTickCounter) ?? 0) + 1;
    await prefs.setInt(_kTickCounter, c);

    // trung bình ~ mỗi 1-2 phút có quà 1 lần
    final rng = Random(now);
    final chance = (c % 6 == 0) && (rng.nextInt(100) < 45);

    if (!chance) return null;

    final t = rng.nextInt(3);
    if (t == 0) {
      pet.addEnergy(10);
      return const GiftResult(GiftType.energy, 10, "Quà bất ngờ");
    } else if (t == 1) {
      pet.addExp(30);
      return const GiftResult(GiftType.exp, 30, "Quà tri thức");
    } else {
      pet.addFood(1);
      return const GiftResult(GiftType.food, 1, "Bánh linh thú");
    }
  }
}
