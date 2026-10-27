# 0003 — Fixed 18-byte record in a raw circular flash partition

## Status

Accepted

## Context

The bridge needs compact, power-loss-safe storage for four probes at roughly a
30 s cadence. A filesystem adds metadata and recovery complexity for a single
fixed-shape stream.

## Decision

Store an 18-byte fixed record: 24-bit sequence, UTC seconds, four i16
temperatures, flags and CRC16. Write it to a raw circular flash partition with
sector headers and oldest-sector erasure, not to LittleFS. Use CRC16/CCITT-FALSE
and validate sentinel/attachment consistency.

## Consequences

Storage is seekable and streamable, and a torn tail is recoverable. Record size
must be exposed through `record_size`, not `sizeof`. Capacity arithmetic is part
of the contract (338,400 records), and boot recovery must scan headers rather
than rely on a filesystem.
