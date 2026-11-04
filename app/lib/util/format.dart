import 'package:intl/intl.dart';

String formatRemaining(Duration d) {
  if (d.isNegative) return '0 min';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  if (days > 0) return '$days j ${hours.toString().padLeft(2, '0')} h';
  if (d.inHours > 0) return '${d.inHours} h ${minutes.toString().padLeft(2, '0')} min';
  if (d.inMinutes > 0) return '$minutes min ${seconds.toString().padLeft(2, '0')} s';
  return '$seconds s';
}

String formatMeeting(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final hm = DateFormat('HH:mm', 'fr_FR').format(d).replaceAll(':', ' h ');
  if (day == today) return "aujourd'hui à $hm";
  if (day == today.add(const Duration(days: 1))) return 'demain à $hm';
  return '${DateFormat('EEEE d MMMM', 'fr_FR').format(d)} à $hm';
}

String formatMessageTime(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return DateFormat('HH:mm', 'fr_FR').format(d);
  }
  return DateFormat('d MMM, HH:mm', 'fr_FR').format(d);
}

const genderLabels = {
  'femme': 'Femme',
  'homme': 'Homme',
  'non_binaire': 'Non binaire',
};

const seekingLabels = {
  'femme': 'Des femmes',
  'homme': 'Des hommes',
  'non_binaire': 'Des personnes non binaires',
};
