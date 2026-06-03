/// integration_test / E2E 向けの送信・遷移カウンタ。
class E2EDiagnostics {
  E2EDiagnostics._();

  static int sendPressed = 0;
  static int insufficientTickets = 0;
  static int subscriptionPrompt = 0;

  static void reset() {
    sendPressed = 0;
    insufficientTickets = 0;
    subscriptionPrompt = 0;
  }
}
