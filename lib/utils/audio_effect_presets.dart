const audioEffectPresets = <String, List<double>>{
  'Flat': [0, 0, 0],
  'Voice': [-0.12, 0.22, 0.18],
  'Warm': [0.28, 0.08, -0.14],
  'Bright': [-0.12, 0.12, 0.32],
};

String audioEffectPresetFor(List<double> gains) {
  for (final entry in audioEffectPresets.entries) {
    var matches = true;
    for (var index = 0; index < 3; index++) {
      if ((entry.value[index] - gains[index]).abs() > 0.01) matches = false;
    }
    if (matches) return entry.key;
  }
  return '';
}
