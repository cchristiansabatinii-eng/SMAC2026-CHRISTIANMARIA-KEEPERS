(function registerKeepersAuthBridge(scope) {
  "use strict";

  const securityHeaders = Object.freeze({
    "cache-control": "no-store",
    "content-security-policy":
      "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
  });

  function textResponse(body, status, extraHeaders) {
    return new Response(body, {
      status,
      headers: {
        ...securityHeaders,
        "content-type": "text/plain; charset=utf-8",
        ...extraHeaders,
      },
    });
  }

  function invalidLinkResponse() {
    return textResponse(
      "This sign-in link is incomplete or has expired. Request a new sign-in link in Keepers.",
      400,
    );
  }

  function redirectResponse(location) {
    return new Response(null, {
      status: 303,
      headers: { ...securityHeaders, location },
    });
  }

  function handleAuthBridgeRequest(request) {
    if (request.method !== "GET") {
      return textResponse(
        "This endpoint can only open from a Keepers sign-in email.",
        405,
        { allow: "GET" },
      );
    }

    let url;
    try {
      url = new URL(request.url);
    } catch (_) {
      return invalidLinkResponse();
    }

    const codes = url.searchParams.getAll("code");
    const attempts = url.searchParams.getAll("attempt");
    if (
      Array.from(url.searchParams.keys()).some(
        (key) => key !== "code" && key !== "attempt",
      ) ||
      codes.length !== 1 ||
      codes[0].trim().length === 0 ||
      codes[0].length > 2048 ||
      attempts.length > 1 ||
      (attempts.length === 1 && !/^[A-Za-z0-9_-]{1,128}$/.test(attempts[0]))
    ) {
      return invalidLinkResponse();
    }

    const encodedCode = encodeURIComponent(codes[0]);
    const encodedAttempt =
      attempts.length === 1 ? `&attempt=${encodeURIComponent(attempts[0])}` : "";
    const callbackQuery = `code=${encodedCode}${encodedAttempt}`;
    const userAgent = request.headers.get("user-agent") || "";
    const location = /android/i.test(userAgent)
      ? `intent://auth-callback?${callbackQuery}#Intent;scheme=keepers;package=app.keepers.keepers;end`
      : `keepers://auth-callback?${callbackQuery}`;

    return redirectResponse(location);
  }

  scope.keepersAuthBridge = Object.freeze({ handleAuthBridgeRequest });
})(globalThis);
