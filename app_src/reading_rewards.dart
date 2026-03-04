import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'pet.dart';

enum GiftType { energy, exp, food }

class GiftResult {
  final GiftType type;
  final int amount;
  GiftResult({required this.type, required this.amount});
}

class ReadingRewards {
  static const _kLastGiftTs = 'last_gift_ts';
  static const _kActiveReadTs = 'active_read_ts';

  static Future<void> markUserActiveReading() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kActiveReadTs, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> _isActive({int withinSeconds = 25}) async {
    final sp = await SharedPreferences.getInstance();
    final ts = sp.getInt(_kActiveReadTs) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - ts) <= withinSeconds * 1000;
  }

  /// Gọi mỗi 10s: nếu active -> +EXP theo thời gian.
  static Future<GiftResult?> tick10s(PetState pet) async {
    if (!await _isActive()) return null;

    // +EXP theo thời gian
    int expGain = 2; // 10s = +2 exp
    if (pet.branch == PetBranch.wisdom) expGain = (expGain * 1.25).round();
    pet.addExp(expGain);

    pet.readSecondsToday += 10;

    // mỗi 60s -> +1 energy (speed nhanh hơn)
    final per = pet.branch == PetBranch.speed ? 45 : 60;
    if (pet.readSecondsToday % per == 0) {
      pet.energy += 1;
    }

    return _maybeGift(pet);
  }

  static Future<GiftResult?> _maybeGift(PetState pet) async {
    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastGift = sp.getInt(_kLastGiftTs) ?? 0;

    const cooldownMs = 3 * 60 * 1000; // 3 phút
    if (now - lastGift < cooldownMs) return null;

    // xác suất ~6% mỗi 10s
    if (Random().nextDouble() > 0.06) return null;

    final roll = Random().nextInt(100);
    GiftResult gift;

    if (roll < 60) {
      final amount = 3 + Random().nextInt(5); // 3-7
      pet.energy += amount;
      gift = GiftResult(type: GiftType.energy, amount: amount);
    } else if (roll < 90) {
      final amount = 10 + Random().nextInt(21); // 10-30
      pet.addExp(amount);
      gift = GiftResult(type: GiftType.exp, amount: amount);
    } else {
      pet.food += 1;
      gift = GiftResult(type: GiftType.food, amount: 1);
    }

    await sp.setInt(_kLastGiftTs, now);
    return gift;
  }
}
