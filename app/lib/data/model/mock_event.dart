/// N2.26 — the mock event-bus catalogue.
library;

/// One fireable event, with the plain-language hint the dev panel shows.
class MockEventSpec {
  const MockEventSpec({
    required this.id,
    required this.label,
    required this.hint,
  });

  final String id;
  final String label;
  final String hint;
}
