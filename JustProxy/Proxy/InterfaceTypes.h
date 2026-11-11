#include <net/if.h>
#include <stdbool.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/sockio.h>

// The SDK's ioctl request macro is not imported into Swift.
static inline bool JPIsInfrastructureWiFi(int socket, const char *name) {
    struct ifreq request = {0};
    strlcpy(request.ifr_name, name, sizeof(request.ifr_name));
    // VPN tunnels can inherit Wi-Fi as their functional type from the underlying interface.
    if (ioctl(socket, SIOCGIFFLAGS, &request) != 0 || (request.ifr_flags & IFF_POINTOPOINT) != 0) {
        return false;
    }
    return ioctl(socket, SIOCGIFFUNCTIONALTYPE, &request) == 0
        && request.ifr_ifru.ifru_functional_type == IFRTYPE_FUNCTIONAL_WIFI_INFRA;
}
