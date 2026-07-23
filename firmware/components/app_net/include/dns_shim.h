/* dns_shim — the UDP/53 half of the captive-portal shim (F8.5, design 05
 * §5.8.1): in AP mode, answer every A query with 192.168.4.1 so Android's
 * connectivity probe resolves to us. Pure codec — bytes in, bytes out —
 * with the socket task as thin glue, so malformed queries, AAAA, and odd
 * classes are host-testable from fixtures. */
#ifndef DNS_SHIM_H
#define DNS_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DNS_SHIM_MAX_RESPONSE 512

/* Builds the response for one query datagram. Returns the response length,
 * or -1 to drop (malformed / not a query / QDCOUNT 0).
 *
 * - A + class IN  → one answer record: `ip`, TTL 60
 * - AAAA          → empty NOERROR (an NXDOMAIN makes some resolvers fail
 *                   over to IPv6 and skip us entirely)
 * - anything else → empty NOERROR
 */
int dns_shim_respond(const uint8_t *query, size_t query_len,
                     const uint8_t ip[4], uint8_t *out, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* DNS_SHIM_H */
