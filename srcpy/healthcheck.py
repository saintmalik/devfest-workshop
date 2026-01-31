import sys
import urllib.request

# HARDENED HEALTHCHECK
# 1. Use 127.0.0.1 to avoid DNS spoofing/hijacking
# 2. Disable proxies to prevent SSRF via environment variables
# 3. Enforce strict timeout to prevent DoS

URL = "http://127.0.0.1:5001/health"


def health_check():
    try:
        # Create an opener that ignores all proxy settings
        proxy_handler = urllib.request.ProxyHandler({})
        opener = urllib.request.build_opener(proxy_handler)

        # Open URL with explicit timeout
        with opener.open(URL, timeout=2) as response:
            if response.status == 200:
                sys.exit(0)
    except Exception:
        pass

    sys.exit(1)


if __name__ == "__main__":
    health_check()
