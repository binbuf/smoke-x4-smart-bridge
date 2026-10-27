# protocol_gen - ESP-IDF wrapper around the committed generated protocol codec.
#
# protocol/gen/records.c is generated from protocol/records.yaml and committed
# (ADR 0013). It is not inside firmware/ so that the host test project, the
# firmware and the Dart package all consume the same output. This component
# exposes it to ESP-IDF without copying or re-generating it at build time.
idf_component_register(
    SRCS "${CMAKE_CURRENT_LIST_DIR}/../../../protocol/gen/records.c"
    INCLUDE_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../protocol/gen"
)
