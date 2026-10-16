int? nextTemplateIndex(List<String> orderedIds, String? lastTemplateId) {
  if (orderedIds.isEmpty) return null;
  return (orderedIds.indexOf(lastTemplateId ?? '') + 1) % orderedIds.length;
}
