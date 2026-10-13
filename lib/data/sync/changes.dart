/// Column changes that two devices can make to the same row without overwriting each other.
///
/// Each change is sent to Appwrite as an atomic operator (or a plain value for [Put]) and applied
/// the same way to the device's own copy, so what the screen shows matches what the server does.
/// The rules mirror the server, checked against the live backend on 2026-10-13:
/// - a decrement that would go below its floor is skipped (the column keeps its value);
/// - an increment that would pass its cap is skipped;
/// - an append keeps duplicates ([Unique] removes them in a later update);
/// - a skipped column never blocks the other columns of the same update.
library;

import 'package:appwrite/appwrite.dart';

sealed class FieldChange {
  const FieldChange();

  /// The value for the `data` map of `updateRow`/`upsertRow`.
  dynamic toWire();

  /// The column after this change, from its value before.
  dynamic applyTo(dynamic current);
}

/// Adds [by]; skipped when the result would pass [max].
class Inc extends FieldChange {
  const Inc(this.by, {this.max});
  final int by;
  final int? max;

  @override
  String toWire() => Operator.increment(by, max);

  @override
  int applyTo(dynamic current) {
    final v = asInt(current);
    final next = v + by;
    return max != null && next > max! ? v : next;
  }

  @override
  String toString() => 'Inc($by${max == null ? '' : ', max $max'})';
}

/// Subtracts [by]; skipped when the result would go below zero.
class Dec extends FieldChange {
  const Dec(this.by);
  final int by;

  @override
  String toWire() => Operator.decrement(by, 0);

  @override
  int applyTo(dynamic current) {
    final v = asInt(current);
    final next = v - by;
    return next < 0 ? v : next;
  }

  @override
  String toString() => 'Dec($by)';
}

/// Sets the column (last writer wins).
class Put extends FieldChange {
  const Put(this.value);
  final dynamic value;

  @override
  dynamic toWire() => value;

  @override
  dynamic applyTo(dynamic current) => value;

  @override
  String toString() => 'Put($value)';
}

/// Appends [values] to a list column.
class Append extends FieldChange {
  const Append(this.values);
  final List<String> values;

  @override
  String toWire() => Operator.arrayAppend(values);

  @override
  List<String> applyTo(dynamic current) => [...asStrings(current), ...values];

  @override
  String toString() => 'Append($values)';
}

/// Removes every occurrence of [values] from a list column.
class Remove extends FieldChange {
  const Remove(this.values);
  final List<String> values;

  @override
  String toWire() => Operator.arrayDiff(values);

  @override
  List<String> applyTo(dynamic current) => [for (final v in asStrings(current)) if (!values.contains(v)) v];

  @override
  String toString() => 'Remove($values)';
}

/// Drops duplicates from a list column, keeping the first of each.
class Unique extends FieldChange {
  const Unique();

  @override
  String toWire() => Operator.arrayUnique();

  @override
  List<String> applyTo(dynamic current) => dedupe(asStrings(current));

  @override
  String toString() => 'Unique()';
}

typedef RowChanges = Map<String, FieldChange>;

/// [row] after [changes], the way the server applies them.
Map<String, dynamic> applyChanges(Map<String, dynamic> row, RowChanges changes) => {
      ...row,
      for (final e in changes.entries) e.key: e.value.applyTo(row[e.key]),
    };

/// The `data` map for an update carrying [changes].
Map<String, dynamic> wireData(RowChanges changes) => {for (final e in changes.entries) e.key: e.value.toWire()};

int asInt(dynamic v, [int d = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);

List<String> asStrings(dynamic v) => v is List ? [for (final e in v) e.toString()] : const [];

List<String> dedupe(Iterable<String> values) {
  final seen = <String>{};
  return [for (final v in values) if (seen.add(v)) v];
}
