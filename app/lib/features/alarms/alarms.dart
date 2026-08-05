/// Alarms: the two-tier rule editor, the delivery verdict, and the alarm log.
///
/// See design 08 §8.3, §8.6, design 09, and newapp §G.
///
/// **`alerts_tab.dart` is gone.** It was a permissions verdict plus a test
/// button occupying a quarter of the primary navigation. Its verdict became
/// `DeliveryBanner` on the screens that need it; its test button moved beside
/// the rules it tests at `/device/alarms`; and its "the rules aren't editable
/// yet" card is obsolete, because they are.
library;

export 'alarm_rule_sheet.dart';
export 'alarm_rules_route.dart';
export 'delivery.dart';
export 'delivery_banner.dart';
