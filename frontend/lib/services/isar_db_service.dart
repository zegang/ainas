import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'db_service.dart';
import 'kv_entry.dart';

class IsarDbService implements DbService {
  final Isar isar;

  IsarDbService(this.isar);

  static Future<IsarDbService> create({String? directory}) async {
    final dir = directory ?? (await getApplicationDocumentsDirectory()).path;
    final isar = await Isar.open(
      [KvEntrySchema],
      directory: dir,
    );
    return IsarDbService(isar);
  }

  @override
  Future<String?> getString(String key) async {
    final entry = await isar.kvEntries.where().keyEqualTo(key).findFirst();
    return entry?.value;
  }

  @override
  Future<void> setString(String key, String value) async {
    await isar.writeTxn(() async {
      final entry = await isar.kvEntries.where().keyEqualTo(key).findFirst();
      if (entry != null) {
        entry.value = value;
        await isar.kvEntries.put(entry);
      } else {
        await isar.kvEntries.put(KvEntry()..key = key..value = value);
      }
    });
  }

  @override
  Future<bool?> getBool(String key) async {
    final val = await getString(key);
    if (val == null) return null;
    return val == 'true';
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await setString(key, value.toString());
  }

  @override
  Future<double?> getDouble(String key) async {
    final val = await getString(key);
    if (val == null) return null;
    return double.tryParse(val);
  }

  @override
  Future<void> setDouble(String key, double value) async {
    await setString(key, value.toString());
  }

  @override
  Future<int?> getInt(String key) async {
    final val = await getString(key);
    if (val == null) return null;
    return int.tryParse(val);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await setString(key, value.toString());
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final val = await getString(key);
    if (val == null) return null;
    return val.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await setString(key, value.join('\n'));
  }

  @override
  Future<void> remove(String key) async {
    await isar.writeTxn(() async {
      final entry = await isar.kvEntries.where().keyEqualTo(key).findFirst();
      if (entry != null) {
        await isar.kvEntries.delete(entry.id);
      }
    });
  }

  Future<void> close() => isar.close();
}
