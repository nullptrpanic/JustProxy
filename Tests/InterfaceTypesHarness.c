#include <errno.h>
#include <net/if.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/sockio.h>

static int interface_ioctl(int socket, unsigned long command, ...) {
    (void)socket;
    va_list arguments;
    va_start(arguments, command);
    struct ifreq *request = va_arg(arguments, struct ifreq *);
    va_end(arguments);

    if (command == SIOCGIFFLAGS) {
        if (strcmp(request->ifr_name, "flags-failed") == 0) {
            errno = ENXIO;
            return -1;
        }
        request->ifr_flags = (short)(IFF_UP | IFF_MULTICAST);
        if (strcmp(request->ifr_name, "utun3") == 0
            || strcmp(request->ifr_name, "ipsec0") == 0) {
            request->ifr_flags |= IFF_POINTOPOINT;
        } else {
            request->ifr_flags |= IFF_BROADCAST;
        }
        return 0;
    }
    if (command == SIOCGIFFUNCTIONALTYPE) {
        if (strcmp(request->ifr_name, "type-failed") == 0) {
            errno = ENXIO;
            return -1;
        }
        request->ifr_ifru.ifru_functional_type = IFRTYPE_FUNCTIONAL_WIFI_INFRA;
        if (strcmp(request->ifr_name, "pdp_ip0") == 0) {
            request->ifr_ifru.ifru_functional_type = IFRTYPE_FUNCTIONAL_CELLULAR;
        } else if (strcmp(request->ifr_name, "awdl0") == 0) {
            request->ifr_ifru.ifru_functional_type = IFRTYPE_FUNCTIONAL_WIFI_AWDL;
        }
        return 0;
    }
    errno = EINVAL;
    return -1;
}

#define ioctl interface_ioctl
#include "../JustProxy/Proxy/InterfaceTypes.h"
#undef ioctl

int main(int argc, char **argv) {
    if (argc != 2) { return 2; }
    printf("%d\n", JPIsInfrastructureWiFi(0, argv[1]));
    return 0;
}
