import 'package:isar/isar.dart';

part 'kv_entry.g.dart';

@collection
class KvEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String key;

  String? value;
}
