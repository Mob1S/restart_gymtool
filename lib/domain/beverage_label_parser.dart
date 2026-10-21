import 'beverage.dart';
import 'beverage_energy.dart';

/// OCR is only transcription. Ambiguous values/bases remain empty for review.
class BeverageLabelDraft {
  final String? energy, volumeMl, name;
  final EnergyUnit? unit;
  final EnergyBasis? basis;
  final String warning;
  const BeverageLabelDraft({
    this.energy,
    this.volumeMl,
    this.name,
    this.unit,
    this.basis,
    required this.warning,
  });
}

BeverageLabelDraft parseBeverageLabel(String text) {
  final normalized = text.replaceAll('：', ':').replaceAll('ｍＬ', 'mL');
  final name = RegExp(
    r'(?:产品名称|品名|product\s*name)\s*[:：]\s*([^\r\n]{1,100})',
    caseSensitive: false,
  ).firstMatch(normalized)?[1]?.trim();
  final per100g = RegExp(
    r'(每\s*100\s*[g克]|per\s*100\s*g|/\s*100\s*g)',
    caseSensitive: false,
  ).hasMatch(normalized);
  final bases = <EnergyBasis>{};
  if (RegExp(
    r'(每\s*100\s*(ml|毫升)|per\s*100\s*ml|/\s*100\s*ml)',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    bases.add(EnergyBasis.per100ml);
  }
  if (RegExp(
    r'(每\s*[份瓶杯]|per\s*(serving|bottle|cup)|/\s*(serving|bottle|cup))',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    bases.add(EnergyBasis.perServing);
  }
  final matches = RegExp(
    r'(?:能量|热量|energy|calories)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(kcal|kJ|千焦|千卡|大卡)',
    caseSensitive: false,
  ).allMatches(normalized).toList();
  final volumes = RegExp(
    r'(?:净含量|净容量|net\s*(?:volume|content))\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(ml|毫升|[lL]|升)(?=\s|$|[)）])',
    caseSensitive: false,
  ).allMatches(normalized).toList();
  String? volume;
  if (volumes.length == 1) {
    final v = volumes.single;
    final unit = v[2]!.toLowerCase();
    volume = (unit == 'l' || unit == '升')
        ? (BeverageEnergy.parse(v[1]!) * BeverageEnergy.parse('1000'))
              .decimalText
        : v[1];
  }
  final usable = !per100g && bases.length == 1 && matches.length == 1;
  return BeverageLabelDraft(
    name: name,
    energy: usable ? matches.single[1] : null,
    unit: usable
        ? (['kj', '千焦'].contains(matches.single[2]!.toLowerCase())
              ? EnergyUnit.kj
              : EnergyUnit.kcal)
        : null,
    basis: !per100g && bases.length == 1 ? bases.single : null,
    volumeMl: volume,
    warning: per100g
        ? '检测到每 100 g；不能按 mL 计算，请核对并提供每份依据。'
        : usable
        ? '已提取标签文字，请逐项核对名称、版本、热量基准和容量后保存。'
        : '未能确定唯一能量值、单位和基准，请对照原图补全；不会猜测热量。',
  );
}
