import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

// Уведы

final FlutterLocalNotificationsPlugin notificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tz_data.initializeTimeZones();
  try {
    // Часовой пояс
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
  } catch (_) {}
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  try {
    await notificationsPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // Android 13+: без явного разрешения уведомления не показываются
    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _scheduleDailyReminder();
  } catch (_) {}
}

Future<void> _scheduleDailyReminder() async {
  try {
    await notificationsPlugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
    tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await notificationsPlugin.zonedSchedule(
      0,
      '💸 Как там денежки?',
      'Запиши траты за сегодня — сундук сам себя не откроет 🎁',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Ежедневное напоминание',
          channelDescription: 'Напоминание записать траты',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  } catch (_) {
    // Что б апк работал даже без разрешения на уведы
  }
}

// Старт

final AppState app = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.instance.init();
  await app.reload();
  runApp(const BxcMoneyApp());
  // Уведомления настраиваем уже после старта, чтобы не держать заставку
  initNotifications();
}

// Тема

class AppColors {
  static const bg = Color(0xFF0F0F0F);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceHigh = Color(0xFF2C2C2E);
  static const critical = Color(0xFF1A2E1A);
  static const criticalBorder = Color(0xFF2E5A2E);
  static const accent = Color(0xFF32D74B);
  static const accentOrange = Color(0xFFFF9F0A);
  static const accentRed = Color(0xFFFF453A);
  static const accentPurple = Color(0xFFBF5AF2);
  static const accentGold = Color(0xFFFFD60A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8E8E93);
}

// Для дат и денег

String _two(int n) => n.toString().padLeft(2, '0');
DateTime dOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String dkey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime parseKey(String s) {
  final parts = s.split('-');
  return DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

String money(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${v.round() < 0 ? '−' : ''}$b ₽';
}

const kWeekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const kMonths = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
];
String dayLabel(DateTime d) =>
    '${kWeekdays[d.weekday - 1]}, ${d.day} ${kMonths[d.month - 1]}';

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

final _rnd = Random();
T pick<T>(List<T> list) => list[_rnd.nextInt(list.length)];

// Для категорий

class Cat {
  final String key;
  final String title;
  final String emoji;
  final Color color;
  final bool isIncome;
  final bool archived; // удалённые категории прячутся, но старые записи с ними живут
  const Cat(this.key, this.title, this.emoji, this.color,
      {this.isIncome = false, this.archived = false});
}

const kDefaultExpenseCats = [
  Cat('sticks', 'Стики', '🚬', Color(0xFF8E8E93)),
  Cat('alco', 'Пиво / вино', '🍷', Color(0xFFFF375F)),
  Cat('food', 'Еда', '🥟', Color(0xFFFF9F0A)),
  Cat('transport', 'Проезд', '🚌', Color(0xFF0A84FF)),
  Cat('home', 'Быт', '🧴', Color(0xFF64D2FF)),
  Cat('fun', 'Развлечения', '🎉', Color(0xFFBF5AF2)),
  Cat('health', 'Здоровье', '💊', Color(0xFF30D158)),
  Cat('other', 'Другое', '✨', Color(0xFFFFD60A)),
];

const kDefaultIncomeCats = [
  Cat('salary', 'Зарплата', '💰', Color(0xFF32D74B), isIncome: true),
  Cat('side', 'Халтурка', '🛠️', Color(0xFF66D4CF), isIncome: true),
  Cat('gift', 'Подарок', '🎁', Color(0xFFFF9F0A), isIncome: true),
  Cat('other_in', 'Другое', '💸', Color(0xFFFFD60A), isIncome: true),
];

// Цвета для новых категорий
const kCatPalette = [
  Color(0xFF8E8E93), Color(0xFFFF375F), Color(0xFFFF9F0A), Color(0xFFFFD60A),
  Color(0xFF32D74B), Color(0xFF66D4CF), Color(0xFF64D2FF), Color(0xFF0A84FF),
  Color(0xFF5E5CE6), Color(0xFFBF5AF2), Color(0xFFAC8E68), Color(0xFFFF6482),
];

const _unknownCat = Cat('?', 'Без категории', '❔', Color(0xFF8E8E93));

Cat catOf(String key) =>
    app.cats.firstWhere((c) => c.key == key, orElse: () => _unknownCat);

// Быстрая кнопка для трат
class Quick {
  final int id;
  final String category;
  final double amount;
  const Quick(this.id, this.category, this.amount);
}

// Награды

const kRarityNames = ['Обычный', 'Редкий', 'Легендарный'];
const kRarityEmoji = ['📦', '💜', '👑'];
const kRarityColors = [
  AppColors.accent,
  AppColors.accentPurple,
  AppColors.accentGold,
];
const kRarityBonus = [5, 15, 40]; // пельмешки за открытие сундука

const kDefaultPool = <List<Object>>[
  ['Час сериала без угрызений совести', 0],
  ['Долгий душ или ванна с музыкой', 0],
  ['Законный вечер без уборки', 0],
  ['Поспать на час дольше', 0],
  ['Танцы под любимый трек на повторе', 0],
  ['Шоколадка до 100 ₽', 0],
  ['Банка любимого пива', 1],
  ['Кофе навынос', 1],
  ['Маска для лица и вечер ухода', 1],
  ['Вещь из вишлиста до 300 ₽', 1],
  ['Заказать вкусняшку до 600 ₽', 2],
  ['Бутылка хорошего вина', 2],
  ['Вылазка с подругой', 2],
];

class Level {
  final int min;
  final String title;
  final String emoji;
  const Level(this.min, this.title, this.emoji);
}

const kLevels = [
  Level(0, 'Транжира в завязке', '🐣'),
  Level(50, 'Пельменный стажёр', '🥟'),
  Level(150, 'Хранительница заначки', '🫙'),
  Level(300, 'Хомяк-накопитель', '🐹'),
  Level(500, 'Гроза кассиров', '🧾'),
  Level(800, 'Финансовая ведьма', '🔮'),
  Level(1200, 'Королева кэшбэка', '👸'),
  Level(1700, 'Скрудж в юбке', '🦆'),
  Level(2500, 'Легенда бюджета', '🏆'),
];

// Переменные

class Period {
  final int id;
  final DateTime start;
  final DateTime payday; // день зарплаты (сам день уже не входит в период)
  final double startBalance;
  final double goal; // сколько отложить
  const Period(this.id, this.start, this.payday, this.startBalance, this.goal);
}

class Tx {
  final int id;
  final DateTime date;
  final double amount;
  final bool isIncome;
  final String category;
  final String note;
  const Tx(this.id, this.date, this.amount, this.isIncome, this.category,
      this.note);
}

class PoolItem {
  final int id;
  final String text;
  final int rarity;
  const PoolItem(this.id, this.text, this.rarity);
}

class OpenedChest {
  final String date;
  final String reward;
  final int rarity;
  const OpenedChest(this.date, this.reward, this.rarity);
}

enum DayStatus { today, success, fail, missed }

class DayInfo {
  final DateTime date;
  final double limit;
  final double spent;
  final DayStatus status;
  final Period period;
  const DayInfo(this.date, this.limit, this.spent, this.status, this.period);
}

class Achievement {
  final String emoji;
  final String title;
  final String desc;
  final bool unlocked;
  const Achievement(this.emoji, this.title, this.desc, this.unlocked);
}

// SQL датабазка

class DB {
  DB._();
  static final DB instance = DB._();
  Database? _db;
  Database get db => _db!;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'bxc_money.db'),
      version: 2,
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _createV2(db);
      },
      onCreate: (db, _) async {
        await _createV2(db);
        await db.execute('''
          CREATE TABLE periods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_date TEXT NOT NULL,
            payday TEXT NOT NULL,
            start_balance REAL NOT NULL,
            goal REAL NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE tx (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            amount REAL NOT NULL,
            is_income INTEGER NOT NULL,
            category TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('CREATE TABLE zero_days (date TEXT PRIMARY KEY)');
        await db.execute('''
          CREATE TABLE chests (
            date TEXT PRIMARY KEY,
            reward TEXT NOT NULL,
            rarity INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE reward_pool (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            rarity INTEGER NOT NULL
          )''');
        final batch = db.batch();
        for (final r in kDefaultPool) {
          batch.insert('reward_pool', {'text': r[0], 'rarity': r[1]});
        }
        await batch.commit(noResult: true);
      },
    );
  }

  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        emoji TEXT NOT NULL,
        color INTEGER NOT NULL,
        is_income INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        sort INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL
      )''');
    final batch = db.batch();
    var i = 0;
    for (final c in [...kDefaultExpenseCats, ...kDefaultIncomeCats]) {
      batch.insert(
        'categories',
        {
          'key': c.key,
          'title': c.title,
          'emoji': c.emoji,
          'color': c.color.value,
          'is_income': c.isIncome ? 1 : 0,
          'archived': 0,
          'sort': i++,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    batch.insert('quick', {'category': 'sticks', 'amount': 230.0});
    await batch.commit(noResult: true);
  }

  Future<List<Cat>> categories() async {
    final rows = await db.query('categories', orderBy: 'sort, rowid');
    return rows
        .map((r) => Cat(
      r['key'] as String,
      r['title'] as String,
      r['emoji'] as String,
      Color(r['color'] as int),
      isIncome: (r['is_income'] as int) == 1,
      archived: (r['archived'] as int) == 1,
    ))
        .toList();
  }

  Future<void> saveCategory(Cat c) async {
    final exists = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM categories WHERE key = ?', [c.key])) ??
        0;
    final data = {
      'title': c.title,
      'emoji': c.emoji,
      'color': c.color.value,
      'is_income': c.isIncome ? 1 : 0,
      'archived': c.archived ? 1 : 0,
    };
    if (exists > 0) {
      await db.update('categories', data, where: 'key = ?', whereArgs: [c.key]);
    } else {
      final maxSort = Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(sort) FROM categories')) ??
          0;
      await db.insert('categories', {...data, 'key': c.key, 'sort': maxSort + 1});
    }
  }

  Future<List<Quick>> quick() async {
    final rows = await db.query('quick', orderBy: 'id');
    return rows
        .map((r) => Quick(
      r['id'] as int,
      r['category'] as String,
      (r['amount'] as num).toDouble(),
    ))
        .toList();
  }

  Future<void> addQuick(String category, double amount) =>
      db.insert('quick', {'category': category, 'amount': amount});

  Future<void> deleteQuick(int id) =>
      db.delete('quick', where: 'id = ?', whereArgs: [id]);

  Future<void> deleteQuickByCategory(String key) =>
      db.delete('quick', where: 'category = ?', whereArgs: [key]);

  Future<List<Period>> periods() async {
    final rows = await db.query('periods', orderBy: 'start_date, id');
    return rows
        .map((r) => Period(
      r['id'] as int,
      parseKey(r['start_date'] as String),
      parseKey(r['payday'] as String),
      (r['start_balance'] as num).toDouble(),
      (r['goal'] as num).toDouble(),
    ))
        .toList();
  }

  Future<List<Tx>> txs() async {
    final rows = await db.query('tx', orderBy: 'date, id');
    return rows
        .map((r) => Tx(
      r['id'] as int,
      parseKey(r['date'] as String),
      (r['amount'] as num).toDouble(),
      (r['is_income'] as int) == 1,
      r['category'] as String,
      (r['note'] as String?) ?? '',
    ))
        .toList();
  }

  Future<Set<String>> zeroDays() async {
    final rows = await db.query('zero_days');
    return rows.map((r) => r['date'] as String).toSet();
  }

  Future<List<OpenedChest>> chests() async {
    final rows = await db.query('chests', orderBy: 'date');
    return rows
        .map((r) => OpenedChest(
      r['date'] as String,
      r['reward'] as String,
      r['rarity'] as int,
    ))
        .toList();
  }

  Future<List<PoolItem>> pool() async {
    final rows = await db.query('reward_pool', orderBy: 'rarity, id');
    return rows
        .map((r) => PoolItem(
      r['id'] as int,
      r['text'] as String,
      r['rarity'] as int,
    ))
        .toList();
  }

  Future<void> addPeriod(
      DateTime start, DateTime payday, double balance, double goal) =>
      db.insert('periods', {
        'start_date': dkey(start),
        'payday': dkey(payday),
        'start_balance': balance,
        'goal': goal,
      });

  Future<void> addTx(DateTime date, double amount, bool isIncome,
      String category, String note) =>
      db.insert('tx', {
        'date': dkey(date),
        'amount': amount,
        'is_income': isIncome ? 1 : 0,
        'category': category,
        'note': note,
      });

  Future<void> deleteTx(int id) =>
      db.delete('tx', where: 'id = ?', whereArgs: [id]);

  Future<void> setZero(DateTime d, bool on) async {
    if (on) {
      await db.insert('zero_days', {'date': dkey(d)},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('zero_days', where: 'date = ?', whereArgs: [dkey(d)]);
    }
  }

  Future<void> openChest(String date, String reward, int rarity) =>
      db.insert('chests', {'date': date, 'reward': reward, 'rarity': rarity},
          conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> addPool(String text, int rarity) =>
      db.insert('reward_pool', {'text': text, 'rarity': rarity});

  Future<void> deletePool(int id) =>
      db.delete('reward_pool', where: 'id = ?', whereArgs: [id]);
}

// Логика

class AppState extends ChangeNotifier {
  List<Period> periods = [];
  List<Tx> txs = [];
  Set<String> zeroDays = {};
  List<OpenedChest> opened = [];
  List<PoolItem> pool = [];
  List<Cat> cats = [];
  List<Quick> quicks = [];

  List<Cat> get expenseCats =>
      cats.where((c) => !c.isIncome && !c.archived).toList();
  List<Cat> get incomeCats =>
      cats.where((c) => c.isIncome && !c.archived).toList();

  // логика-2
  final Map<String, double> spentByDay = {};
  final Map<String, double> incomeByDay = {};
  final Map<String, List<Tx>> txByDay = {};
  final List<DayInfo> days = [];
  final List<String> chestsEarned = [];
  final Set<int> finishedOkPeriods = {};
  int streak = 0;
  int maxStreak = 0;
  int coins = 0;
  int successDays = 0;

  Future<void> reload() async {
    periods = await DB.instance.periods();
    txs = await DB.instance.txs();
    zeroDays = await DB.instance.zeroDays();
    opened = await DB.instance.chests();
    pool = await DB.instance.pool();
    cats = await DB.instance.categories();
    quicks = await DB.instance.quick();
    _recompute();
    notifyListeners();
  }

  DateTime get today => dOnly(DateTime.now());

  void _recompute() {
    spentByDay.clear();
    incomeByDay.clear();
    txByDay.clear();
    days.clear();
    chestsEarned.clear();
    finishedOkPeriods.clear();

    for (final t in txs) {
      final k = dkey(t.date);
      txByDay.putIfAbsent(k, () => []).add(t);
      if (t.isIncome) {
        incomeByDay[k] = (incomeByDay[k] ?? 0) + t.amount;
      } else {
        spentByDay[k] = (spentByDay[k] ?? 0) + t.amount;
      }
    }

    final t0 = today;
    for (int i = 0; i < periods.length; i++) {
      final per = periods[i];
      DateTime end = per.payday; // не включительно
      if (i + 1 < periods.length && periods[i + 1].start.isBefore(end)) {
        end = periods[i + 1].start;
      }
      double available = per.startBalance;
      for (var d = per.start;
      d.isBefore(end) && !d.isAfter(t0);
      d = addDays(d, 1)) {
        final k = dkey(d);
        available += incomeByDay[k] ?? 0;
        final left = max(1, daysBetween(d, per.payday));
        final limit = max(0.0, (available - per.goal) / left);
        final spent = spentByDay[k] ?? 0;
        final logged = txByDay.containsKey(k) || zeroDays.contains(k);
        final DayStatus st;
        if (d == t0) {
          st = DayStatus.today;
        } else if (!logged) {
          st = DayStatus.missed;
        } else if (spent <= limit + 0.5) {
          st = DayStatus.success;
        } else {
          st = DayStatus.fail;
        }
        days.add(DayInfo(d, limit, spent, st, per));
        available -= spent;
      }
      // Период закончился (зарплата пришла) и копилка цела, получение ачивки хомяками
      if (end == per.payday && !t0.isBefore(per.payday) && available >= per.goal) {
        finishedOkPeriods.add(per.id);
      }
    }

    int run = 0;
    maxStreak = 0;
    coins = 0;
    successDays = 0;
    for (final di in days) {
      if (di.status == DayStatus.today) continue;
      if (di.status == DayStatus.success) {
        run++;
        successDays++;
        coins += 10 + min(20, ((di.limit - di.spent) / 50).floor());
        if (di.spent == 0) coins += 5;
        if (run % 3 == 0) chestsEarned.add(dkey(di.date));
      } else {
        run = 0;
      }
      maxStreak = max(maxStreak, run);
    }
    streak = run;
    for (final c in opened) {
      coins += kRarityBonus[c.rarity.clamp(0, 2)];
    }
  }


  DayInfo? get todayInfo {
    if (days.isEmpty) return null;
    final last = days.last;
    return last.date == today ? last : null;
  }

  Period? get lastPeriod => periods.isEmpty ? null : periods.last;

  double balanceOf(Period per) {
    double b = per.startBalance;
    for (final t in txs) {
      if (t.date.isBefore(per.start)) continue;
      b += t.isIncome ? t.amount : -t.amount;
    }
    return b;
  }

  double get balance => lastPeriod == null ? 0 : balanceOf(lastPeriod!);

  int get daysLeft =>
      lastPeriod == null ? 0 : max(0, daysBetween(today, lastPeriod!.payday));

  List<String> get unopenedChests {
    final done = opened.map((c) => c.date).toSet();
    return chestsEarned.where((d) => !done.contains(d)).toList();
  }

  bool isZero(DateTime d) => zeroDays.contains(dkey(d));
  List<Tx> txOn(DateTime d) => txByDay[dkey(d)] ?? [];

  Level get level => kLevels.lastWhere((l) => coins >= l.min);
  Level? get nextLevel {
    final i = kLevels.indexOf(level);
    return i + 1 < kLevels.length ? kLevels[i + 1] : null;
  }

  List<Achievement> get achievements {
    final past = days.where((d) => d.status != DayStatus.today).toList();
    bool hasCat(DateTime d, String cat) =>
        txOn(d).any((t) => !t.isIncome && t.category == cat);
    bool logged(DayInfo d) =>
        d.status == DayStatus.success || d.status == DayStatus.fail;

    int soberRun = 0, soberMax = 0;
    for (final d in past) {
      if (logged(d) && !hasCat(d.date, 'alco')) {
        soberRun++;
        soberMax = max(soberMax, soberRun);
      } else {
        soberRun = 0;
      }
    }

    final loggedCount = past.where(logged).length;
    final zero = past.any((d) => d.status == DayStatus.success && d.spent == 0);
    final half = past.any((d) =>
    d.status == DayStatus.success && d.limit > 0 && d.spent <= d.limit / 2);
    final noSticks = past.any((d) => logged(d) && !hasCat(d.date, 'sticks'));

    return [
      Achievement('🐣', 'Первый шаг', 'Записать первую трату или доход',
          txs.isNotEmpty),
      Achievement('🙌', 'Нулевой день', 'Прожить день вообще без трат', zero),
      Achievement('🧠', 'Мастер лимита', 'Потратить за день не больше половины лимита', half),
      Achievement('🌬️', 'Глоток воздуха', 'День без стиков', noSticks),
      Achievement('🧃', 'Трезвая тройка',
          '3 записанных дня подряд без пива и вина', soberMax >= 3),
      Achievement('📒', 'Летописец', 'Записать 10 дней ($loggedCount/10)',
          loggedCount >= 10),
      Achievement('🔥', 'Неделя в огне', 'Серия 7 успешных дней (рекорд: $maxStreak)',
          maxStreak >= 7),
      Achievement('💎', 'Алмазная серия', '14 успешных дней подряд',
          maxStreak >= 14),
      Achievement('🎁', 'Охотница за сундуками',
          'Открыть 5 сундуков (${opened.length}/5)', opened.length >= 5),
      Achievement('🐹', 'Хомяк дотянул', 'Дожить до зарплаты с целой копилкой',
          finishedOkPeriods.isNotEmpty),
    ];
  }

  // действия

  Future<void> addTx(DateTime date, double amount, bool isIncome,
      String category, String note) async {
    await DB.instance.addTx(dOnly(date), amount, isIncome, category, note);
    if (!isIncome) await DB.instance.setZero(date, false);
    await reload();
  }

  Future<void> deleteTx(Tx t) async {
    await DB.instance.deleteTx(t.id);
    await reload();
  }

  Future<void> setZero(DateTime d, bool on) async {
    await DB.instance.setZero(d, on);
    await reload();
  }

  Future<void> startPeriod(DateTime payday, double balance, double goal) async {
    await DB.instance.addPeriod(today, payday, balance, goal);
    await reload();
  }

  Future<OpenedChest> openChest(String date) async {
    final roll = _rnd.nextInt(100);
    int rarity = roll < 5 ? 2 : (roll < 30 ? 1 : 0);
    var candidates = pool.where((p) => p.rarity == rarity).toList();
    if (candidates.isEmpty) candidates = pool;
    String reward;
    if (candidates.isEmpty) {
      reward = 'Просто гордись собой 😎';
      rarity = 0;
    } else {
      final item = pick(candidates);
      reward = item.text;
      rarity = item.rarity;
    }
    await DB.instance.openChest(date, reward, rarity);
    await reload();
    return OpenedChest(date, reward, rarity);
  }

  Future<void> addPool(String text, int rarity) async {
    await DB.instance.addPool(text, rarity);
    await reload();
  }

  Future<void> deletePool(PoolItem item) async {
    await DB.instance.deletePool(item.id);
    await reload();
  }

  Future<void> saveCategory(Cat c) async {
    await DB.instance.saveCategory(c);
    await reload();
  }

  // Удаление = архив. категория пропадает из выбора, но старые траты с ней остаются в истории и статистике.
  Future<void> archiveCategory(Cat c) async {
    await DB.instance.saveCategory(Cat(c.key, c.title, c.emoji, c.color,
        isIncome: c.isIncome, archived: true));
    await DB.instance.deleteQuickByCategory(c.key);
    await reload();
  }

  Future<void> addQuick(String category, double amount) async {
    await DB.instance.addQuick(category, amount);
    await reload();
  }

  Future<void> deleteQuick(Quick q) async {
    await DB.instance.deleteQuick(q.id);
    await reload();
  }
}

// Приложение

class BxcMoneyApp extends StatelessWidget {
  const BxcMoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BXC Money',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.criticalBorder,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.surfaceHigh,
          contentTextStyle: TextStyle(color: AppColors.textPrimary),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    const screens = [
      TodayScreen(),
      HistoryScreen(),
      StatsScreen(),
      RewardsScreen(),
    ];

    return Scaffold(
      body: screens[_idx],
      bottomNavigationBar: AnimatedBuilder(
        animation: app,
        builder: (context, _) {
          final chests = app.unopenedChests.length;
          return NavigationBar(
            selectedIndex: _idx,
            onDestinationSelected: (i) => setState(() => _idx = i),
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.today_rounded), label: 'Сегодня'),
              const NavigationDestination(
                  icon: Icon(Icons.receipt_long_rounded), label: 'История'),
              const NavigationDestination(
                  icon: Icon(Icons.bar_chart_rounded), label: 'Статистика'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: chests > 0,
                  label: Text('$chests'),
                  child: const Icon(Icons.card_giftcard_rounded),
                ),
                label: 'Плюшки',
              ),
            ],
          );
        },
      ),
    );
  }
}

// Виджеты

class _Card extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? border;
  final EdgeInsets padding;
  const _Card({
    required this.child,
    this.color,
    this.border,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: border != null ? Border.all(color: border!, width: 1.5) : null,
      ),
      child: child,
    );
  }
}

class _TxTile extends StatelessWidget {
  final Tx tx;
  final bool showDate;
  const _TxTile(this.tx, {this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final c = catOf(tx.category);
    return Dismissible(
      key: ValueKey('tx${tx.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.accentRed),
      ),
      confirmDismiss: (_) async {
        await app.deleteTx(tx);
        return true;
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(c.emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(
          tx.note.isNotEmpty ? tx.note : c.title,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        subtitle: Text(
          showDate ? '${c.title} · ${dayLabel(tx.date)}' : c.title,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Text(
          '${tx.isIncome ? '+' : '−'}${money(tx.amount)}',
          style: TextStyle(
            color: tx.isIncome ? AppColors.accent : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, {this.color = AppColors.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

String statusEmoji(DayStatus s) {
  switch (s) {
    case DayStatus.today:
      return '⏳';
    case DayStatus.success:
      return '✅';
    case DayStatus.fail:
      return '💥';
    case DayStatus.missed:
      return '💤';
  }
}

// Кнопочки

Future<void> showAddTxSheet(BuildContext context,
    {bool income = false, DateTime? date, bool pickDate = false}) async {
  final before = app.todayInfo;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddTxSheet(
      income: income,
      date: date ?? app.today,
      pickDate: pickDate,
    ),
  );
  if (result != true || !context.mounted) return;

  final ti = app.todayInfo;
  String msg;
  if (income) {
    msg = pick(['Денежка пришла! 🤑', 'Богатеем 💰', 'Лимит подрос 📈']);
  } else if (ti != null && before != null) {
    final left = ti.limit - ti.spent;
    if (left < 0 && before.limit - before.spent >= 0) {
      msg = pick([
        'Ой. Лимит пробит 🫠 Завтра отыграемся',
        'Перебор на ${money(-left)}. Пельмени тебя не осудят 🥟',
        'Сундук смотрит с укором 📦',
      ]);
    } else if (left < 0) {
      msg = 'Записала. Перебор уже ${money(-left)} 😬';
    } else {
      msg = pick([
        'Записала! На сегодня ещё ${money(left)}',
        'Учтено ✍️ Осталось ${money(left)}',
        'Есть! В запасе ${money(left)} 💪',
      ]);
    }
  } else {
    msg = 'Записала ✍️';
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

class _AddTxSheet extends StatefulWidget {
  final bool income;
  final DateTime date;
  final bool pickDate;
  const _AddTxSheet(
      {required this.income, required this.date, required this.pickDate});

  @override
  State<_AddTxSheet> createState() => _AddTxSheetState();
}

class _AddTxSheetState extends State<_AddTxSheet> {
  late bool _income = widget.income;
  late DateTime _date = widget.date;
  late String _cat = _firstKey(widget.income);

  String _firstKey(bool income) {
    final list = income ? app.incomeCats : app.expenseCats;
    return list.isEmpty ? '?' : list.first.key;
  }
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setIncome(bool v) {
    setState(() {
      _income = v;
      _cat = _firstKey(v);
    });
  }

  Future<void> _save() async {
    final v = double.tryParse(
        _amount.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (v == null || v <= 0) return;
    await app.addTx(_date, v, _income, _cat, _note.text.trim());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = _income ? app.incomeCats : app.expenseCats;
    final accent = _income ? AppColors.accent : AppColors.accentOrange;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('💸 Трата'),
                  selected: !_income,
                  onSelected: (_) => _setIncome(false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('💰 Доход'),
                  selected: _income,
                  onSelected: (_) => _setIncome(true),
                ),
                const Spacer(),
                if (widget.pickDate)
                  TextButton.icon(
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(dayLabel(_date)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2024),
                        lastDate: app.today,
                      );
                      if (d != null) setState(() => _date = dOnly(d));
                    },
                  )
                else
                  Text(dayLabel(_date),
                      style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                  color: accent, fontSize: 36, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '0',
                suffixText: '₽',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accent)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accent, width: 2)),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cats
                  .map<Widget>((c) => ChoiceChip(
                label: Text('${c.emoji} ${c.title}'),
                selected: _cat == c.key,
                selectedColor: c.color.withOpacity(0.35),
                onSelected: (_) => setState(() => _cat = c.key),
              ))
                  .followedBy([
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Своя'),
                  onPressed: () async {
                    final key = await showCategoryEditor(context,
                        isIncome: _income);
                    if (key != null && mounted) setState(() => _cat = key);
                  },
                ),
              ]).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'На что? (необязательно)',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _save,
                child: const Text('Записать',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showPeriodSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _PeriodSheet(),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet();

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late final TextEditingController _balance;
  late final TextEditingController _goal;
  late DateTime _payday;

  @override
  void initState() {
    super.initState();
    final last = app.lastPeriod;
    _balance = TextEditingController(
        text: last != null ? app.balance.round().toString() : '');
    _goal = TextEditingController(
        text: last != null ? last.goal.round().toString() : '');
    final t = app.today;
    if (last != null && last.payday.isAfter(t)) {
      _payday = last.payday;
    } else {
      _payday = t.day < 20
          ? DateTime(t.year, t.month, 20)
          : DateTime(t.year, t.month + 1, 20);
    }
    _balance.addListener(() => setState(() {}));
    _goal.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _balance.dispose();
    _goal.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final days = max(1, daysBetween(app.today, _payday));
    final bal = _num(_balance);
    final goal = _num(_goal);
    final perDay = max(0.0, (bal - goal) / days);

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      suffixText: '₽',
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.surfaceHigh)),
      focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 2)),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🗓️ Новый период',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Начнётся сегодня и продлится до зарплаты',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _balance,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 20),
              decoration: deco('Сколько сейчас на карте'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _goal,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 20),
              decoration: deco('Сколько хочу отложить'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Зарплата',
                  style: TextStyle(color: AppColors.textSecondary)),
              subtitle: Text(dayLabel(_payday),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 18)),
              trailing: const Icon(Icons.edit_calendar_rounded,
                  color: AppColors.accent),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _payday,
                  firstDate: addDays(app.today, 1),
                  lastDate: addDays(app.today, 120),
                );
                if (d != null) setState(() => _payday = dOnly(d));
              },
            ),
            const SizedBox(height: 8),
            _Card(
              color: AppColors.critical,
              border: AppColors.criticalBorder,
              child: Row(
                children: [
                  const Text('🧮', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      bal <= goal
                          ? 'Копилка больше, чем денег на карте 🤔'
                          : '$days ${plural(days, 'день', 'дня', 'дней')} до зарплаты → '
                          'можно ${money(perDay)} в день',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: bal <= 0
                    ? null
                    : () async {
                  await app.startPeriod(_payday, bal, goal);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Поехали 🚀',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Еще категории и кнопки

Future<String?> showCategoryEditor(BuildContext context,
    {required bool isIncome, Cat? existing}) {
  final emojiCtrl = TextEditingController(text: existing?.emoji ?? '');
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  Color color = existing?.color ?? pick(kCatPalette);

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          existing == null
              ? (isIncome ? 'Новая категория дохода' : 'Новая категория трат')
              : 'Категория',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: emojiCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28),
                      decoration: const InputDecoration(
                        hintText: '☕',
                        counterText: '',
                      ),
                      maxLength: 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: titleCtrl,
                      autofocus: existing == null,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'Название',
                        hintStyle: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Эмодзи — с обычной клавиатуры телефона',
                  style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: kCatPalette
                    .map((c) => GestureDetector(
                  onTap: () => setD(() => color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: color.value == c.value
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                  ),
                ))
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                await app.archiveCategory(existing);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Удалить',
                  style: TextStyle(color: AppColors.accentRed)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () async {
              final title = titleCtrl.text.trim();
              if (title.isEmpty) return;
              final emoji =
              emojiCtrl.text.trim().isEmpty ? '🏷️' : emojiCtrl.text.trim();
              final key = existing?.key ??
                  'c${DateTime.now().millisecondsSinceEpoch}';
              await app.saveCategory(
                  Cat(key, title, emoji, color, isIncome: isIncome));
              if (ctx.mounted) Navigator.pop(ctx, key);
            },
            child: const Text('Сохранить',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCategoriesSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _CategoriesSheet(),
  );
}

class _CategoriesSheet extends StatefulWidget {
  const _CategoriesSheet();

  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  final _amount = TextEditingController();
  String? _quickCat;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _addQuick() async {
    final v = double.tryParse(
        _amount.text.replaceAll(',', '.').replaceAll(' ', ''));
    final cat = _quickCat;
    if (v == null || v <= 0 || cat == null) return;
    await app.addQuick(cat, v);
    _amount.clear();
    if (mounted) FocusScope.of(context).unfocus();
  }

  Widget _title(String s) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(s,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16)),
  );

  Widget _catTile(Cat c) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(c.emoji, style: const TextStyle(fontSize: 18)),
    ),
    title: Text(c.title,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
    trailing:
    const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 18),
    onTap: () =>
        showCategoryEditor(context, isIncome: c.isIncome, existing: c),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final exp = app.expenseCats;
        final inc = app.incomeCats;
        if (_quickCat != null && !exp.any((c) => c.key == _quickCat)) {
          _quickCat = null;
        }
        _quickCat ??= exp.isEmpty ? null : exp.first.key;

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: ListView(
              shrinkWrap: true,
              children: [
                // ── quick buttons ──
                const Text('⚡ Быстрые кнопки',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 4),
                const Text(
                    'Появляются на главном экране: одно касание — трата записана. '
                        'Удобно для того, что покупаешь часто.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                if (app.quicks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Пока нет ни одной',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ...app.quicks.map((q) {
                  final c = catOf(q.category);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(c.emoji, style: const TextStyle(fontSize: 22)),
                    title: Text(c.title,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(money(q.amount),
                        style: TextStyle(color: c.color)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary),
                      onPressed: () => app.deleteQuick(q),
                    ),
                  );
                }),
                if (exp.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButton<String>(
                          value: _quickCat,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceHigh,
                          underline: const SizedBox(),
                          items: exp
                              .map((c) => DropdownMenuItem(
                            value: c.key,
                            child: Text('${c.emoji} ${c.title}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.textPrimary)),
                          ))
                              .toList(),
                          onChanged: (v) => setState(() => _quickCat = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Сумма',
                            suffixText: '₽',
                            hintStyle:
                            TextStyle(color: AppColors.textSecondary),
                          ),
                          onSubmitted: (_) => _addQuick(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_rounded,
                            color: AppColors.accent, size: 32),
                        onPressed: _addQuick,
                      ),
                    ],
                  ),

                // расходы
                _title('💸 Категории трат'),
                ...exp.map(_catTile),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новая категория трат'),
                  onPressed: () => showCategoryEditor(context, isIncome: false),
                ),

                // доходы
                _title('💰 Категории доходов'),
                ...inc.map(_catTile),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новая категория дохода'),
                  onPressed: () => showCategoryEditor(context, isIncome: true),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Удалённая категория пропадает из выбора, но старые записи с ней остаются в истории.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// текущий день

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  String _mood(DayInfo ti) {
    if (ti.limit <= 0) return 'Лимит на нуле. Пельмени — наше всё 🥟';
    final r = ti.spent / ti.limit;
    if (ti.spent == 0) return 'Пока ни копейки. Красота ✨';
    if (r <= 0.5) return 'Идёшь шикарно, кошелёк мурчит 😼';
    if (r <= 0.85) return 'Нормально, но притормози чуток 🚦';
    if (r <= 1.0) return 'Впритык! Дальше только смотреть 👀';
    return 'Перебор. Ничего, завтра лимит подстроится 🫂';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final t = app.today;
        final ti = app.todayInfo;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            title: Text(dayLabel(t),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                tooltip: 'Категории и кнопки',
                icon: const Icon(Icons.category_rounded,
                    color: AppColors.textSecondary),
                onPressed: () => showCategoriesSheet(context),
              ),
              IconButton(
                tooltip: 'Период',
                icon: const Icon(Icons.tune_rounded,
                    color: AppColors.textSecondary),
                onPressed: () => showPeriodSheet(context),
              ),
            ],
          ),
          body: ti == null ? _noPeriod(context) : _body(context, ti),
        );
      },
    );
  }

  Widget _noPeriod(BuildContext context) {
    final ended = app.lastPeriod != null;
    final hamster = ended && app.finishedOkPeriods.contains(app.lastPeriod!.id);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ended ? (hamster ? '🐹' : '💰') : '👋',
                style: const TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            Text(
              ended
                  ? (hamster
                  ? 'Дотянула до зарплаты с целой копилкой! Легенда.'
                  : 'Период закончился. Зарплата пришла?')
                  : 'Привет! Давай настроим бюджет до зарплаты',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Скажи, сколько денег на карте, когда зарплата и сколько хочешь отложить — дальше я сама посчитаю лимит на каждый день.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
              icon: const Icon(Icons.rocket_launch_rounded, color: Colors.black),
              label: Text(ended ? 'Новый период' : 'Настроить',
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: () => showPeriodSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DayInfo ti) {
    final t = app.today;
    final left = ti.limit - ti.spent;
    final ratio = ti.limit <= 0 ? 1.0 : (ti.spent / ti.limit).clamp(0.0, 1.0);
    final color = left < 0
        ? AppColors.accentRed
        : ratio > 0.85
        ? AppColors.accentOrange
        : AppColors.accent;
    final todayTx = app.txOn(t).reversed.toList();
    final hasExpense = todayTx.any((x) => !x.isIncome);
    final zero = app.isZero(t);
    final streakDots = app.streak % 3;
    final chests = app.unopenedChests.length;
    final todayOk = left >= 0 && (todayTx.isNotEmpty || zero);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // ── hero ──
        _Card(
          color: left < 0 ? const Color(0xFF2E1A1A) : AppColors.critical,
          border: left < 0 ? AppColors.accentRed : AppColors.criticalBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(left >= 0 ? 'Можно потратить сегодня' : 'Перебор на сегодня',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(end: left.abs()),
                duration: const Duration(milliseconds: 500),
                builder: (_, v, __) => Text(
                  money(v),
                  style: TextStyle(
                      color: color, fontSize: 44, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 10,
                  backgroundColor: AppColors.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Лимит ${money(ti.limit)} · потрачено ${money(ti.spent)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(_mood(ti),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),

        // статы
        Row(
          children: [
            _MiniStat('На карте', money(app.balance)),
            const SizedBox(width: 8),
            _MiniStat('До зарплаты',
                '${app.daysLeft} ${plural(app.daysLeft, 'день', 'дня', 'дней')}'),
            const SizedBox(width: 8),
            _MiniStat('Копилка 🐷', money(ti.period.goal),
                color: AppColors.accentGold),
          ],
        ),
        const SizedBox(height: 12),

        // серия
        _Card(
          child: Row(
            children: [
              Text(app.streak > 0 ? '🔥' : '🧊',
                  style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${app.streak} ${plural(app.streak, 'день', 'дня', 'дней')} подряд в лимите',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ...List.generate(3, (i) {
                          final filled = i < streakDots;
                          final todayDot = i == streakDots && todayOk;
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? AppColors.accentOrange
                                  : AppColors.surfaceHigh,
                              border: todayDot
                                  ? Border.all(
                                  color: AppColors.accentOrange, width: 2)
                                  : null,
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                        const Text('🎁', style: TextStyle(fontSize: 20)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      todayOk
                          ? 'Сегодня пока в лимите — держись до ночи!'
                          : 'До сундука ${3 - streakDots} ${plural(3 - streakDots, 'успешный день', 'успешных дня', 'успешных дней')}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (chests > 0)
                Badge(
                  label: Text('$chests'),
                  child: const Text('🎁', style: TextStyle(fontSize: 32)),
                ),
            ],
          ),
        ),

        // еще действия
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentOrange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.remove_rounded, color: Colors.black),
                  label: const Text('Трата',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  onPressed: () => showAddTxSheet(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.add_rounded, color: Colors.black),
                  label: const Text('Доход',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  onPressed: () => showAddTxSheet(context, income: true),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...app.quicks.map((q) {
              final c = catOf(q.category);
              return ActionChip(
                avatar: Text(c.emoji),
                label: Text('${c.title} · ${money(q.amount)}'),
                onPressed: () async {
                  await app.addTx(t, q.amount, false, q.category, '');
                  if (context.mounted) {
                    final ti2 = app.todayInfo;
                    final left = ti2 == null ? 0 : ti2.limit - ti2.spent;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          content: Text(left >= 0
                              ? '${c.emoji} Записано! На сегодня ещё ${money(left)}'
                              : '${c.emoji} Записано. Перебор ${money(-left)} 😬')));
                  }
                },
              );
            }),
            ActionChip(
              avatar: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Кнопки'),
              onPressed: () => showCategoriesSheet(context),
            ),
            if (!hasExpense)
              ActionChip(
                avatar: Text(zero ? '✅' : '🙌'),
                label: Text(zero ? 'День без трат (отменить)' : 'Сегодня без трат'),
                onPressed: () => app.setZero(t, !zero),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // сегодня
        if (todayTx.isNotEmpty) ...[
          const Text('Сегодня',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Смахни влево, чтобы удалить',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ...todayTx.map((x) => _TxTile(x)),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: Text('Пока пусто. Запиши первую трату или отметь день без трат 👆',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
      ],
    );
  }
}

// ИСТОРИЯ

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final list = app.days.reversed.toList();
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            title: const Text('История',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
          floatingActionButton: app.periods.isEmpty
              ? null
              : FloatingActionButton(
            backgroundColor: AppColors.accent,
            onPressed: () => showAddTxSheet(context, pickDate: true),
            child: const Icon(Icons.add_rounded, color: Colors.black),
          ),
          body: list.isEmpty
              ? const Center(
              child: Text('Записей пока нет',
                  style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            itemCount: list.length,
            itemBuilder: (ctx, i) => _DayBlock(list[i]),
          ),
        );
      },
    );
  }
}

class _DayBlock extends StatelessWidget {
  final DayInfo di;
  const _DayBlock(this.di);

  @override
  Widget build(BuildContext context) {
    final tx = app.txOn(di.date);
    final hasExpense = tx.any((t) => !t.isIncome);
    final zero = app.isZero(di.date);
    final color = di.status == DayStatus.fail
        ? AppColors.accentRed
        : di.status == DayStatus.success
        ? AppColors.accent
        : AppColors.textSecondary;

    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      border: di.status == DayStatus.today ? AppColors.accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(statusEmoji(di.status), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayLabel(di.date),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold)),
                    Text(
                      di.status == DayStatus.missed
                          ? 'Не записано — серия прервалась'
                          : '${money(di.spent)} из ${money(di.limit)}',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded,
                    color: AppColors.textSecondary),
                color: AppColors.surfaceHigh,
                onSelected: (v) {
                  if (v == 'add') showAddTxSheet(context, date: di.date);
                  if (v == 'zero') app.setZero(di.date, !zero);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'add', child: Text('➕ Добавить запись')),
                  if (!hasExpense)
                    PopupMenuItem(
                        value: 'zero',
                        child: Text(zero
                            ? '↩️ Убрать «без трат»'
                            : '🙌 Трат не было')),
                ],
              ),
            ],
          ),
          if (zero && !hasExpense)
            const Padding(
              padding: EdgeInsets.only(left: 34, top: 4, bottom: 4),
              child: Text('День без трат 🙌',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ...tx.reversed.map((t) => _TxTile(t)),
        ],
      ),
    );
  }
}

// Основные статы

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final per = app.lastPeriod;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            title: const Text('Статистика',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
          body: per == null
              ? const Center(
              child: Text('Сначала настрой период',
                  style: TextStyle(color: AppColors.textSecondary)))
              : _body(per),
        );
      },
    );
  }

  Widget _body(Period per) {
    final txs = app.txs.where((t) => !t.date.isBefore(per.start)).toList();
    final income = txs.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final spent = txs.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final days = app.days.where((d) => d.period.id == per.id).toList();
    final ok = days.where((d) => d.status == DayStatus.success).length;
    final bad = days.where((d) => d.status == DayStatus.fail).length;
    final missed = days.where((d) => d.status == DayStatus.missed).length;

    final byCat = <String, double>{};
    for (final t in txs.where((t) => !t.isIncome)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxCat = cats.isEmpty ? 1.0 : cats.first.value;

    final maxBar = days.fold<double>(
        1, (m, d) => max(m, max(d.spent, d.limit)));
    final elapsed = max(1, days.length);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${per.start.day} ${kMonths[per.start.month - 1]} → '
                  'зарплата ${per.payday.day} ${kMonths[per.payday.month - 1]}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              _row('Было на старте', money(per.startBalance)),
              _row('Пришло', '+${money(income)}', AppColors.accent),
              _row('Потрачено', '−${money(spent)}', AppColors.accentOrange),
              _row('В среднем в день', money(spent / elapsed)),
              const Divider(color: AppColors.surfaceHigh, height: 24),
              _row('Сейчас на карте', money(app.balanceOf(per)), AppColors.textPrimary, true),
              _row('Цель копилки', money(per.goal), AppColors.accentGold),
            ],
          ),
        ),
        Row(
          children: [
            _MiniStat('Успешных', '✅ $ok', color: AppColors.accent),
            const SizedBox(width: 8),
            _MiniStat('Перебор', '💥 $bad', color: AppColors.accentRed),
            const SizedBox(width: 8),
            _MiniStat('Пропущено', '💤 $missed'),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('По дням',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Столбик — траты, белая черта — лимит',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: days.map((d) {
                    final c = d.status == DayStatus.fail
                        ? AppColors.accentRed
                        : d.status == DayStatus.success
                        ? AppColors.accent
                        : d.status == DayStatus.today
                        ? AppColors.accentOrange
                        : AppColors.surfaceHigh;
                    const h = 110.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 24,
                            height: h,
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  width: 24,
                                  height: max(4.0, d.spent / maxBar * h),
                                  decoration: BoxDecoration(
                                    color: c,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                Positioned(
                                  bottom: d.limit / maxBar * h,
                                  child: Container(
                                      width: 24, height: 2, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('${d.date.day}',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Куда ушли деньги',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 12),
              if (cats.isEmpty)
                const Text('Трат пока нет 😇',
                    style: TextStyle(color: AppColors.textSecondary)),
              ...cats.map((e) {
                final c = catOf(e.key);
                final share = spent == 0 ? 0 : (e.value / spent * 100).round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${c.emoji} ${c.title}',
                              style: const TextStyle(color: AppColors.textPrimary)),
                          const Spacer(),
                          Text('${money(e.value)} · $share%',
                              style: TextStyle(
                                  color: c.color, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: e.value / maxCat,
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation(c.color),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String l, String v,
      [Color c = AppColors.textPrimary, bool bold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(l, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(v,
              style: TextStyle(
                  color: c,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: bold ? 18 : 15)),
        ],
      ),
    );
  }
}

// ОСНОВНЫЕ НАГРАДЫ

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final lvl = app.level;
        final next = app.nextLevel;
        final progress = next == null
            ? 1.0
            : (app.coins - lvl.min) / (next.min - lvl.min);
        final unopened = app.unopenedChests;
        final ach = app.achievements;
        final achDone = ach.where((a) => a.unlocked).length;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            title: const Text('Плюшки',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Мои награды'),
                onPressed: () => _showPool(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── level ──
              _Card(
                color: AppColors.critical,
                border: AppColors.criticalBorder,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(lvl.emoji, style: const TextStyle(fontSize: 44)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Уровень ${kLevels.indexOf(lvl) + 1}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              Text(lvl.title,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20)),
                            ],
                          ),
                        ),
                        Text('${app.coins} 🥟',
                            style: const TextStyle(
                                color: AppColors.accentGold,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: AppColors.surfaceHigh,
                        valueColor:
                        const AlwaysStoppedAnimation(AppColors.accentGold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      next == null
                          ? 'Максимальный уровень. Ты — финансовый босс 😎'
                          : 'До «${next.title}» ${next.emoji} ещё ${next.min - app.coins} 🥟',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),


              if (unopened.isNotEmpty)
                ...unopened.map((d) => _Card(
                  border: AppColors.accentOrange,
                  child: Row(
                    children: [
                      const _WigglingChest(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Сундук ждёт!',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            Text('За 3 дня в лимите до ${dayLabel(parseKey(d))}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentOrange),
                        onPressed: () => showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => _ChestDialog(date: d),
                        ),
                        child: const Text('Открыть',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ))
              else
                _Card(
                  child: Row(
                    children: [
                      const Text('🔒', style: TextStyle(fontSize: 32)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Следующий сундук — через ${3 - app.streak % 3} '
                              '${plural(3 - app.streak % 3, 'успешный день', 'успешных дня', 'успешных дней')}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── how to earn ──
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Как копить пельмешки 🥟',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    SizedBox(height: 8),
                    Text(
                      '• День в лимите — +10\n'
                          '• Каждые 50 ₽, оставшиеся от лимита — +1 (до +20)\n'
                          '• День совсем без трат — ещё +5\n'
                          '• 3 дня подряд в лимите — сундук 🎁\n'
                          '• Сундук: обычный +5, редкий +15, легендарный +40\n'
                          '• Не записала день — серия сгорает 💤',
                      style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                    ),
                  ],
                ),
              ),

              // ачивочки
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Text('Ачивки · $achDone/${ach.length}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: ach.map((a) => _AchCard(a)).toList(),
              ),

              // история сундучков
              if (app.opened.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                  child: Text('Открытые сундуки',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                ...app.opened.reversed.map((c) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Text(kRarityEmoji[c.rarity.clamp(0, 2)],
                      style: const TextStyle(fontSize: 24)),
                  title: Text(c.reward,
                      style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                      '${kRarityNames[c.rarity.clamp(0, 2)]} · ${dayLabel(parseKey(c.date))}',
                      style: TextStyle(
                          color: kRarityColors[c.rarity.clamp(0, 2)],
                          fontSize: 12)),
                )),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showPool(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _PoolSheet(),
    );
  }
}

class _AchCard extends StatelessWidget {
  final Achievement a;
  const _AchCard(this.a);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: a.unlocked ? AppColors.critical : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: a.unlocked ? AppColors.accent : AppColors.surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: a.unlocked ? 1 : 0.3,
            child: Text(a.emoji, style: const TextStyle(fontSize: 30)),
          ),
          const Spacer(),
          Text(a.title,
              style: TextStyle(
                  color: a.unlocked
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(a.desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _WigglingChest extends StatefulWidget {
  const _WigglingChest();

  @override
  State<_WigglingChest> createState() => _WigglingChestState();
}

class _WigglingChestState extends State<_WigglingChest>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        // Покачивание в первые 40% цикла, потом пауза
        final t = _c.value;
        final angle = t < 0.4 ? sin(t / 0.4 * pi * 4) * 0.15 : 0.0;
        return Transform.rotate(angle: angle, child: child);
      },
      child: const Text('🎁', style: TextStyle(fontSize: 36)),
    );
  }
}

class _ChestDialog extends StatefulWidget {
  final String date;
  const _ChestDialog({required this.date});

  @override
  State<_ChestDialog> createState() => _ChestDialogState();
}

class _ChestDialogState extends State<_ChestDialog>
    with SingleTickerProviderStateMixin {
  OpenedChest? _result;
  bool _opening = false;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    await _shake.forward();
    final r = await app.openChest(widget.date);
    if (mounted) setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final rarity = r?.rarity.clamp(0, 2) ?? 0;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
            color: r == null ? AppColors.accentOrange : kRarityColors[rarity],
            width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: r == null
              ? Column(
            key: const ValueKey('closed'),
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _shake,
                builder: (_, child) => Transform.rotate(
                  angle: sin(_shake.value * pi * 10) *
                      0.2 *
                      _shake.value,
                  child: Transform.scale(
                      scale: 1 + _shake.value * 0.3, child: child),
                ),
                child: const Text('🎁', style: TextStyle(fontSize: 96)),
              ),
              const SizedBox(height: 16),
              const Text('Три дня в лимите!',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Что же внутри?..',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                ),
                onPressed: _opening ? null : _open,
                child: Text(_opening ? 'Открываю...' : 'Открыть!',
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          )
              : Column(
            key: const ValueKey('open'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kRarityEmoji[rarity],
                  style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 8),
              Text(kRarityNames[rarity].toUpperCase(),
                  style: TextStyle(
                      color: kRarityColors[rarity],
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              Text(r.reward,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('+${kRarityBonus[rarity]} 🥟',
                  style: const TextStyle(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: kRarityColors[rarity]),
                onPressed: () => Navigator.pop(context),
                child: const Text('Заслужила 😌',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoolSheet extends StatefulWidget {
  const _PoolSheet();

  @override
  State<_PoolSheet> createState() => _PoolSheetState();
}

class _PoolSheetState extends State<_PoolSheet> {
  final _text = TextEditingController();
  int _rarity = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final s = _text.text.trim();
    if (s.isEmpty) return;
    await app.addPool(s, _rarity);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎁 Что может выпасть из сундука',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Шансы: обычный 70%, редкий 25%, легендарный 5%. Придумай свои!',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: app.pool
                      .map((it) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(kRarityEmoji[it.rarity.clamp(0, 2)],
                        style: const TextStyle(fontSize: 20)),
                    title: Text(it.text,
                        style: const TextStyle(
                            color: AppColors.textPrimary)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary),
                      onPressed: () => app.deletePool(it),
                    ),
                  ))
                      .toList(),
                ),
              ),
              const Divider(color: AppColors.surfaceHigh),
              Wrap(
                spacing: 8,
                children: List.generate(
                  3,
                      (i) => ChoiceChip(
                    label: Text('${kRarityEmoji[i]} ${kRarityNames[i]}'),
                    selected: _rarity == i,
                    selectedColor: kRarityColors[i].withOpacity(0.3),
                    onSelected: (_) => setState(() => _rarity = i),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Новая награда...',
                        hintStyle: TextStyle(color: AppColors.textSecondary),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded,
                        color: AppColors.accent, size: 32),
                    onPressed: _add,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}