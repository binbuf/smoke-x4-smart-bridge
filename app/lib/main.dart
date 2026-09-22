/// Entry point. All real work happens in `app/bootstrap.dart`.
library;

import 'dart:async';

import 'app/bootstrap.dart';

void main() => unawaited(bootstrap());
