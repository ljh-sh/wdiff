/^# Packages using this file: / {
  s/# Packages using this file://
  ta
  :a
  s/ wdiff / wdiff /
  tb
  s/ $/ wdiff /
  :b
  s/^/# Packages using this file:/
}
