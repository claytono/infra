const READ_METHODS = new Set(["GET", "HEAD"]);
const SLUG = "[a-z0-9][a-z0-9-]{0,63}";
const ARTWORK_PATH = new RegExp(`^/api/v1/feeds/${SLUG}/artwork$`);

function isBlockedPath(pathname) {
  if (pathname === "/ui" || pathname.startsWith("/ui/")) {
    return true;
  }

  if (pathname === "/api" || pathname.startsWith("/api/")) {
    return !ARTWORK_PATH.test(pathname);
  }

  return false;
}

function parseBasicAuth(header) {
  if (!header) {
    return null;
  }

  const match = header.trim().match(/^Basic\s+(\S+)$/i);
  if (!match) {
    return null;
  }

  try {
    const decoded = atob(match[1]);
    const separator = decoded.indexOf(":");
    if (separator < 0) {
      return null;
    }

    return {
      username: decoded.slice(0, separator),
      password: decoded.slice(separator + 1),
    };
  } catch {
    return null;
  }
}

function unauthorized() {
  return new Response("Unauthorized\n", {
    status: 401,
    headers: {
      "Cache-Control": "no-store",
      "WWW-Authenticate": 'Basic realm="MinusPod feed", charset="UTF-8"',
    },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (isBlockedPath(url.pathname)) {
      return new Response("Not found\n", {
        status: 404,
        headers: {
          "Cache-Control": "no-store",
        },
      });
    }

    if (!READ_METHODS.has(request.method)) {
      return new Response("Method not allowed\n", {
        status: 405,
        headers: {
          "Allow": "GET, HEAD",
          "Cache-Control": "no-store",
        },
      });
    }

    if (!env.BASIC_USER || !env.BASIC_PASS) {
      return unauthorized();
    }

    const credentials = parseBasicAuth(request.headers.get("Authorization"));
    if (
      !credentials ||
      credentials.username !== env.BASIC_USER ||
      credentials.password !== env.BASIC_PASS
    ) {
      return unauthorized();
    }

    const headers = new Headers(request.headers);
    headers.delete("Authorization");

    return fetch(new Request(request, { headers }));
  },
};
