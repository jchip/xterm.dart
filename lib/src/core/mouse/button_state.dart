enum TerminalMouseButtonState {
  up,

  down,

  /// The pointer moved while this button was held (DECSET 1002 button-event
  /// tracking), or with no button held (DECSET 1003 any-event tracking).
  moved,
}
