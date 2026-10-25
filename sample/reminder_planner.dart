// © 2025-2026 Adrián (Adrifib). All rights reserved.
// Shown for illustration only: this file may not be copied, modified or reused.
// Excerpt from a private Flutter project: pure-Dart logic with no plugin dependencies.

import 'package:intl/intl.dart';

/// Horas de aviso configurables (minutos desde medianoche).
class ReminderSchedule {
  /// Aviso de la mañana (por defecto 09:00).
  final int morningMinutes;

  /// Aviso de la tarde/noche (por defecto 20:00).
  final int eveningMinutes;

  const ReminderSchedule({
    this.morningMinutes = 9 * 60,
    this.eveningMinutes = 20 * 60,
  });
}

class PlannedReminder {
  final DateTime at;
  final String title;
  final String body;

  const PlannedReminder({required this.at, required this.title, required this.body});

  @override
  String toString() => '${DateFormat('EEE dd/MM HH:mm').format(at)} · $title · $body';
}

/// Decide cuándo avisar de un cambio de sensor o cánula según la hora a la
/// que caduca. Es lógica pura (sin plugins) para poder razonarla y probarla.
///
/// Reglas:
/// - Caduca temprano (antes de la hora de mañana + 1h, p. ej. antes de las 10:00):
///   · el día anterior por la mañana, para llevar recambio si vas a estar fuera;
///   · el día anterior por la tarde/noche, para dejarlo preparado.
/// - Caduca más tarde (media mañana, tarde o noche):
///   · el día anterior por la tarde/noche, para dejarlo preparado;
///   · ese mismo día por la mañana.
/// - Siempre, 1 hora antes, si cae entre las 08:00 y las 23:00 y no hay
///   otro aviso en la hora previa.
/// Los avisos que ya han pasado se descartan.
class ReminderPlanner {
  static const int _wakeStart = 8 * 60;
  static const int _wakeEnd = 23 * 60;
  static const Duration _finalNoticeLead = Duration(hours: 1);

  /// [subject] con artículo, p. ej. 'el sensor Simplera' o 'la cánula'.
  /// [shortName] para el título, p. ej. 'Sensor Simplera' o 'Cánula'.
  static List<PlannedReminder> plan({
    required DateTime expiry,
    required DateTime now,
    required String subject,
    required String shortName,
    ReminderSchedule schedule = const ReminderSchedule(),
  }) {
    if (!expiry.isAfter(now)) return const [];

    final hhmm = DateFormat('HH:mm').format(expiry);
    final expiryMinutes = expiry.hour * 60 + expiry.minute;
    final day = DateTime(expiry.year, expiry.month, expiry.day);
    final dayBefore = DateTime(expiry.year, expiry.month, expiry.day - 1);

    DateTime at(DateTime d, int minutes) =>
        DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);

    final reminders = <PlannedReminder>[];
    final isEarly = expiryMinutes < schedule.morningMinutes + 60;

    if (isEarly) {
      // Antes de las 06:00 se lee mejor como "esta noche" desde el día anterior
      final when = expiryMinutes < 6 * 60 ? 'esta noche a las $hhmm' : 'mañana a primera hora ($hhmm)';
      reminders.add(PlannedReminder(
        at: at(dayBefore, schedule.morningMinutes),
        title: '$shortName: cambio ${expiryMinutes < 6 * 60 ? 'esta noche' : 'mañana temprano'}',
        body: 'Caduca $when. Si vas a estar fuera de casa, llévate el recambio.',
      ));
      reminders.add(PlannedReminder(
        at: at(dayBefore, schedule.eveningMinutes),
        title: '$shortName: déjalo preparado',
        body: 'Caduca $when. Deja el cambio preparado esta noche.',
      ));
    } else {
      reminders.add(PlannedReminder(
        at: at(dayBefore, schedule.eveningMinutes),
        title: '$shortName: cambio mañana',
        body: 'Mañana ${_partOfDay(expiryMinutes)} a las $hhmm caduca $subject. Déjalo preparado.',
      ));
      reminders.add(PlannedReminder(
        at: at(day, schedule.morningMinutes),
        title: '$shortName: cambio hoy',
        body: 'Hoy ${_partOfDay(expiryMinutes)} a las $hhmm caduca $subject.',
      ));
    }

    final finalAt = expiry.subtract(_finalNoticeLead);
    final finalMinutes = finalAt.hour * 60 + finalAt.minute;
    final inWakingHours = finalMinutes >= _wakeStart && finalMinutes < _wakeEnd;
    final tooCloseToOther = reminders.any((r) =>
        !r.at.isAfter(finalAt) && finalAt.difference(r.at) < const Duration(hours: 1));
    if (inWakingHours && !tooCloseToOther) {
      reminders.add(PlannedReminder(
        at: finalAt,
        title: '$shortName: queda 1 hora',
        body: 'A las $hhmm caduca $subject. Ten el recambio a mano.',
      ));
    }

    return reminders.where((r) => r.at.isAfter(now)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  /// Avisos de una tarea, con las mismas horas que los del equipo.
  ///
  /// - Fecha exacta (cita, recoger algo un día concreto): el día antes por la
  ///   tarde/noche y ese día por la mañana; si tiene hora, también 1 hora antes
  ///   (entre 08:00 y 23:00 y sin otro aviso en la hora previa). Si la hora es
  ///   anterior al aviso de la mañana, ese aviso se omite.
  /// - "Disponible desde" (p. ej. recoger insulina): un aviso ese día por la
  ///   mañana diciendo que ya se puede hacer.
  static List<PlannedReminder> planTask({
    required DateTime day,
    required String title,
    required bool isExactDate,
    int? startMinutes,
    required DateTime now,
    ReminderSchedule schedule = const ReminderSchedule(),
  }) {
    DateTime at(DateTime d, int minutes) =>
        DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
    final d = DateTime(day.year, day.month, day.day);
    final dayBefore = DateTime(day.year, day.month, day.day - 1);
    final reminders = <PlannedReminder>[];

    if (!isExactDate) {
      reminders.add(PlannedReminder(
        at: at(d, schedule.morningMinutes),
        title: 'Ya puedes: $title',
        body: 'Desde hoy puedes hacerlo. Márcala como hecha en Tareas cuando esté.',
      ));
    } else {
      final hhmm = startMinutes == null
          ? null
          : '${(startMinutes ~/ 60).toString().padLeft(2, '0')}:${(startMinutes % 60).toString().padLeft(2, '0')}';
      reminders.add(PlannedReminder(
        at: at(dayBefore, schedule.eveningMinutes),
        title: 'Mañana: $title',
        body: hhmm == null ? 'Lo tienes mañana. Déjalo preparado.' : 'Mañana a las $hhmm. Déjalo preparado.',
      ));
      if (startMinutes == null || startMinutes > schedule.morningMinutes) {
        reminders.add(PlannedReminder(
          at: at(d, schedule.morningMinutes),
          title: 'Hoy: $title',
          body: hhmm == null ? 'Lo tienes hoy.' : 'Hoy a las $hhmm.',
        ));
      }
      if (startMinutes != null) {
        final finalAt = at(d, startMinutes).subtract(_finalNoticeLead);
        final finalMinutes = finalAt.hour * 60 + finalAt.minute;
        final inWakingHours = finalMinutes >= _wakeStart && finalMinutes < _wakeEnd;
        final tooCloseToOther = reminders.any((r) =>
            !r.at.isAfter(finalAt) && finalAt.difference(r.at) < const Duration(hours: 1));
        if (inWakingHours && !tooCloseToOther) {
          reminders.add(PlannedReminder(
            at: finalAt,
            title: 'En 1 hora: $title',
            body: 'A las $hhmm.',
          ));
        }
      }
    }

    return reminders.where((r) => r.at.isAfter(now)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  static String _partOfDay(int minutes) {
    if (minutes < 14 * 60) return 'por la mañana';
    if (minutes < 21 * 60) return 'por la tarde';
    return 'por la noche';
  }
}
