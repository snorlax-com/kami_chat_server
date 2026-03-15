import 'package:flutter_driver/driver_extension.dart';
import 'main_runner_io.dart' if (dart.library.html) 'main_runner_web.dart' as runner;

void main() async {
  if (String.fromEnvironment('INTEGRATION_TEST_E2E', defaultValue: 'false') == 'true') {
    enableFlutterDriverExtension();
  }
  await runner.runAppAsync();
}
