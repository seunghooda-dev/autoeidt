String formatSeconds(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final remain = total % 60;
  final decimal = ((seconds - seconds.floor()) * 10).round();
  if (decimal == 0) {
    return '$minutes:${remain.toString().padLeft(2, '0')}';
  }
  return '$minutes:${remain.toString().padLeft(2, '0')}.$decimal';
}
