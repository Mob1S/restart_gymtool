int? nextTemplateIndex(List<String> orderedIds, String? lastTemplateId) {
  if (orderedIds.isEmpty) return null;
  return (orderedIds.indexOf(lastTemplateId ?? '') + 1) % orderedIds.length;
}

String? recommendDay(List<String> orderedDayIds, String? latestDayId) {
  if (orderedDayIds.isEmpty) return null;
  final index = orderedDayIds.indexOf(latestDayId ?? '');
  return orderedDayIds[index < 0 ? 0 : (index + 1) % orderedDayIds.length];
}
